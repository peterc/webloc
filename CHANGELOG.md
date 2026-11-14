# Changelog

## Unreleased

- Read XML plist files with a built-in single-pass parser and remove the `plist`
  gem dependency. The gem passed `<data>` elements to `Marshal.load` and took
  quadratic time on unterminated comments.
- Reject XML files that are truncated, have a key without a value, have text
  outside elements, or have a comment inside a key or the URL string. A
  non-string `URL` value in XML always raises `CorruptedFileError`.

## 0.4.0

- Rewrite binary plist reading to follow object references and offsets, supporting
  short URLs, additional metadata, and different object orders.
- Fix binary output for long URLs and support lengths beyond 65,535 characters.
- Add Unicode URL support, writing UTF-16 strings and reading them as UTF-8.
- Recover historical long-URL files affected by earlier versions' offset bugs.
- Reject malformed files with a `WeblocError` subclass instead of returning
  partial URLs. Public methods and error classes remain unchanged.
- Require Ruby 3.0 or newer.
- Retain XML support, the original tests and fixtures, and the existing binary
  encoding for short ASCII URLs. Add README example tests, independent plist
  interoperability checks, and CI coverage.
