// node --test test/ (npm test). The barcode scanner's hand-off to the page (src/Scanner.tsx, src/WebShell.tsx).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { barcodeScript, cleanBarcode } from '../src/barcode.ts'

test('cleanBarcode: keeps product and book barcodes (EAN-8 to EAN-14), digits only', () => {
  assert.equal(cleanBarcode('9780064400558'), '9780064400558') // a book's ISBN-13
  assert.equal(cleanBarcode(' 016000275287 '), '016000275287') // UPC-A
  assert.equal(cleanBarcode('96385074'), '96385074') // EAN-8
  for (const bad of ['', '1234567', '123456789012345', '978-0064400558', 'https://example.com', '<script>']) assert.equal(cleanBarcode(bad), null, bad)
})

test('barcodeScript: tells the page what was scanned, or that it was closed', () => {
  const got: unknown[] = []
  const run = (js: string) => new Function('window', 'CustomEvent', js)({ dispatchEvent: (e: { type: string; detail: unknown }) => got.push([e.type, e.detail]) }, function (this: Record<string, unknown>, type: string, o: { detail: unknown }) { this.type = type; this.detail = o.detail })
  run(barcodeScript('9780064400558'))
  run(barcodeScript(null))
  assert.deepEqual(got, [['kinwall:barcode', '9780064400558'], ['kinwall:barcode', null]])
})
