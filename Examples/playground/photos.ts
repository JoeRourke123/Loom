import { probeIf, findImage, INTERACTIVE, IRREVERSIBLE } from './probe';

// pick needs a tap; save writes into the photo library and Loom has no API to take it back out.
export async function photosSuite() {
  const existing = await findImage();

  return [
    // Resolves to a project-relative filename (not an absolute path), same convention as camera.
    await probeIf(INTERACTIVE, 'photos.pick', 'opens the photo picker', () => Loom.photos.pick()),

    await probeIf(
      IRREVERSIBLE && existing !== null,
      'photos.save',
      existing === null
        ? 'no image in the project folder — drop a .jpg beside main.ts, or run camera.capture first'
        : 'writes to the photo library, nothing can remove it again',
      () => Loom.photos.save(existing as string),
    ),
  ];
}
