import { probe, probeIf, findImage, INTERACTIVE } from './probe';

// capture needs the camera and a shutter tap. ocr and barcode are pure Vision calls against a
// file already in the project folder, so they run unattended — if there's an image to run on.
export async function cameraSuite() {
  const results = [];

  results.push(await probeIf(INTERACTIVE, 'camera.capture', 'opens the camera', () => Loom.camera.capture()));

  // Re-read after capture: if the tap above produced a file, ocr/barcode get something real.
  const image = await findImage();
  const why = 'no image in the project folder — drop a .jpg beside main.ts, or enable INTERACTIVE';

  results.push(await probeIf(image !== null, 'camera.ocr', why, async () => {
    const text = await Loom.camera.ocr(image as string);
    return text === '' ? `no text found in ${image}` : text;
  }));

  results.push(await probeIf(image !== null, 'camera.barcode', why, async () => {
    const code = await Loom.camera.barcode(image as string);
    return code === '' ? `no barcode found in ${image}` : code;
  }));

  results.push(await probe('camera.ocr (missing file)', async () => {
    try {
      await Loom.camera.ocr('definitely-not-here.jpg');
    } catch (err) {
      return `rejects with: ${(err as any)?.message ?? err}`;
    }
    throw new Error('OCR on a missing file resolved');
  }));

  return results;
}
