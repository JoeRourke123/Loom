import { probe } from './probe';

// A property bag, not methods — a snapshot taken when the run started. Nothing to await.
// batteryLevel is null on the simulator, which is expected and not a failure.
export async function deviceSuite() {
  return [
    await probe('device.batteryLevel', () => {
      const level = Loom.device.batteryLevel;
      return level === null ? 'null — normal on the simulator' : `${Math.round(level * 100)}%`;
    }),
    await probe('device.isCharging', () => Loom.device.isCharging),
    await probe('device.model', () => Loom.device.model),
    await probe('device.systemVersion', () => Loom.device.systemVersion),
  ];
}
