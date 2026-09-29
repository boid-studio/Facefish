"""Eyelid maths shared by sculpt_eyelids.py (rest pose) and make_face_shapes.py (blink / wide / squint).

The Head is open behind each eyeball: the rim of that hole is the edge of the lids, and the socket is
a set of edge loops around it (ring 0 = the rim, 1, 2, ... outwards). Lids move by sliding those loops
along a sphere around the eye centre:
  - closing ("to"): the upper rim goes to a seam elevation, and ring k lands k/K of the way back from
    the seam to where it was, so the loops spread evenly over the eyeball; the lower lid meets it
  - relative ("by"): every ring shifts by delta * (1 - k/K) degrees
Loops that end up over the eye are pushed onto a shell just outside the eyeball (KEEP_OUT x radius on
the cage), so the subdivided lid still covers the ball. The eye corners move least.
Angles are degrees in head space: elevation above the eye centre (+y up), azimuth atan2(x, z).
"""
from collections import deque

import numpy as np


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def socket_axes(P, c, rim_idx):
    """fwd: out of the socket (towards the rim's centre); up: world up made perpendicular; side."""
    # the rim encircles the eye (it can pass right through the eye centre), so the socket axis is the
    # normal of the rim's best-fit plane, turned to point out of the head
    Q = P[rim_idx] - P[rim_idx].mean(axis=0)
    fwd = np.linalg.svd(Q, full_matrices=False)[2][-1]
    if fwd @ (c - np.array([0.0, -0.42, 0.0])) < 0:
        fwd = -fwd
    up = np.array([0, 1.0, 0]) - fwd[1] * fwd
    up /= np.linalg.norm(up)
    side = np.cross(up, fwd)
    return fwd, up, side


def pitch_coords(P, c, axes):
    """pitch: angle around the side axis (0 = out of the socket, +90 = up); lat: towards the side axis."""
    fwd, up, side = axes
    rel = P - c
    dist = np.linalg.norm(rel, axis=1)
    pitch = np.degrees(np.arctan2(rel @ up, rel @ fwd))
    lat = np.degrees(np.arcsin(np.clip(rel @ side / np.maximum(dist, 1e-6), -1, 1)))
    return dist, pitch, lat


def from_pitch(c, axes, dist, pitch, lat):
    fwd, up, side = axes
    a, b = np.radians(pitch), np.radians(lat)
    d = (np.cos(b) * np.cos(a))[:, None] * fwd + (np.cos(b) * np.sin(a))[:, None] * up + np.sin(b)[:, None] * side
    return c + d * dist[:, None]


def rings(n_verts, edges, rim_idx, max_ring, near_mask):
    """BFS depth from the rim through edges, limited to near_mask; -1 elsewhere."""
    adj = [[] for _ in range(n_verts)]
    for a, b in edges:
        adj[a].append(b)
        adj[b].append(a)
    ring = -np.ones(n_verts, dtype=int)
    q = deque()
    for i in rim_idx:
        ring[i] = 0
        q.append(i)
    while q:
        i = q.popleft()
        if ring[i] >= max_ring:
            continue
        for j in adj[i]:
            if ring[j] < 0 and near_mask[j]:
                ring[j] = ring[i] + 1
                q.append(j)
    return ring


def eye_frame(P, c, rim_idx):
    axes = socket_axes(P, c, rim_idx)
    dist, pitch, lat = pitch_coords(P, c, axes)
    rp = pitch[rim_idx]
    mid = (rp.max() + rp.min()) / 2
    corner = 1 - sstep(84, 90, np.abs(lat))      # rotating about the side axis already keeps the corners still
    return axes, dist, pitch, lat, mid, corner


def move_lids(P, c, r, ring, K_up, K_low, frame, allowed, keep_out,
              upper_to=None, lower_to=None, upper_by=0.0, lower_by=0.0):
    """New positions for P. *_to: absolute rim pitch in degrees (closing); *_by: relative shift."""
    axes, dist, pitch, lat, mid, corner = frame
    up = pitch >= mid
    K = np.where(up, K_up, K_low)
    inring = (ring >= 0) & (ring <= K)
    f = np.where(inring, 1 - ring / np.maximum(K, 1), 0.0)          # 1 at the rim, 0 at ring K
    new = pitch.copy()
    if upper_to is not None:
        new = np.where(up & inring, upper_to + (pitch - upper_to) * (1 - f), new)
    else:
        new = np.where(up & inring, np.minimum(100, pitch + upper_by * f), new)
    if lower_to is not None:
        new = np.where(~up & inring, lower_to + (pitch - lower_to) * (1 - f), new)
    else:
        new = np.where(~up & inring, np.maximum(-100, pitch + lower_by * f), new)
    w = allowed * corner * inring
    p_w = pitch + (new - pitch) * w
    moved = inring & (np.abs(p_w - pitch) > 0.5)
    # loops that slide over the eye go on the shell; the rim tucks in just under it
    new_d = np.where(moved & (ring >= 1), np.maximum(dist, keep_out * r), dist)
    new_d = np.where(moved & (ring == 0), np.maximum(dist, 0.97 * r), new_d)
    d_w = dist + (new_d - dist) * w
    newp = from_pitch(c, axes, d_w, p_w, lat)
    newp[w < 1e-4] = P[w < 1e-4]
    return newp
