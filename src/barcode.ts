// The barcode scanner's hand-off (src/Scanner.tsx): the page (web/src/native.ts in the kinwall repo)
// asks with {type: 'scanBarcode'} and hears back through a 'kinwall:barcode' event.

/** A product or book barcode (EAN-8 up to EAN-14, so ISBN-13 and UPC-A too) as digits, else null. */
export function cleanBarcode(data: string): string | null {
  const s = data.trim()
  return /^\d{8,14}$/.test(s) ? s : null
}

/** Script for the page: the scanned digits, or null when the scanner was closed. */
export const barcodeScript = (code: string | null) =>
  `window.dispatchEvent(new CustomEvent('kinwall:barcode', { detail: ${JSON.stringify(code)} })); true;`
