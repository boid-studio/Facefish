/**
 * Minimal OSC 1.0 decoder. Handles messages and (nested) bundles, and the
 * argument types Face Cap uses (`i`, `f`) plus `s`, `b`, `d`, `h`, `T`, `F`,
 * `N`, `I` so unexpected packets don't throw the parser off.
 */

export type OscArg = number | string | boolean | null | Uint8Array | bigint;

export interface OscMessage {
  address: string;
  args: OscArg[];
}

const textDecoder = new TextDecoder();

function align4(n: number): number {
  return (n + 3) & ~3;
}

function readString(view: DataView, offset: number): [string, number] {
  const bytes = new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
  let end = offset;
  while (end < bytes.length && bytes[end] !== 0) end++;
  const str = textDecoder.decode(bytes.subarray(offset, end));
  // Strings are null terminated and padded to a multiple of 4 bytes.
  return [str, align4(end + 1)];
}

function readBlob(view: DataView, offset: number): [Uint8Array, number] {
  const size = view.getInt32(offset, false);
  const start = offset + 4;
  const blob = new Uint8Array(view.buffer, view.byteOffset + start, size);
  return [blob, align4(start + size)];
}

function decodeMessage(view: DataView, offset: number, end: number): OscMessage {
  const [address, afterAddress] = readString(view, offset);
  let cursor = afterAddress;
  const args: OscArg[] = [];

  if (cursor >= end) return { address, args };

  const [tags, afterTags] = readString(view, cursor);
  cursor = afterTags;
  if (!tags.startsWith(',')) return { address, args };

  for (let i = 1; i < tags.length; i++) {
    const tag = tags[i];
    switch (tag) {
      case 'i':
        args.push(view.getInt32(cursor, false));
        cursor += 4;
        break;
      case 'f':
        args.push(view.getFloat32(cursor, false));
        cursor += 4;
        break;
      case 'd':
        args.push(view.getFloat64(cursor, false));
        cursor += 8;
        break;
      case 'h':
        args.push(view.getBigInt64(cursor, false));
        cursor += 8;
        break;
      case 's':
      case 'S': {
        const [s, next] = readString(view, cursor);
        args.push(s);
        cursor = next;
        break;
      }
      case 'b': {
        const [b, next] = readBlob(view, cursor);
        args.push(b);
        cursor = next;
        break;
      }
      case 'T':
        args.push(true);
        break;
      case 'F':
        args.push(false);
        break;
      case 'N':
        args.push(null);
        break;
      case 'I':
        args.push(Infinity);
        break;
      default:
        // Unknown tag: we can't know its size, so stop parsing this message.
        return { address, args };
    }
  }
  return { address, args };
}

/**
 * Decode one OSC packet (a message or a bundle) into a flat list of
 * messages. Bundle timetags are ignored; Face Cap streams in real time.
 */
export function decodeOscPacket(data: ArrayBuffer | Uint8Array): OscMessage[] {
  const view =
    data instanceof Uint8Array
      ? new DataView(data.buffer, data.byteOffset, data.byteLength)
      : new DataView(data);
  const out: OscMessage[] = [];
  decodeInto(view, 0, view.byteLength, out);
  return out;
}

function decodeInto(view: DataView, offset: number, end: number, out: OscMessage[]): void {
  if (end - offset < 4) return;
  const first = view.getUint8(offset);
  if (first === 0x23 /* '#' */) {
    const [header, afterHeader] = readString(view, offset);
    if (header !== '#bundle') return;
    let cursor = afterHeader + 8; // skip 64-bit timetag
    while (cursor + 4 <= end) {
      const size = view.getInt32(cursor, false);
      cursor += 4;
      if (size < 0 || cursor + size > end) break;
      decodeInto(view, cursor, cursor + size, out);
      cursor += size;
    }
  } else if (first === 0x2f /* '/' */) {
    out.push(decodeMessage(view, offset, end));
  }
}
