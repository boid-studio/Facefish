import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'se.boid.facefish',
  appName: 'Facefish',
  webDir: 'dist',
  ios: {
    contentInset: 'never',
    backgroundColor: '#04101c',
  },
};

export default config;
