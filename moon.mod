// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "daqing/moon-xmpp"

version = "0.9.5"

readme = "README.mbt.md"

repository = "https://github.com/daqing/moon-xmpp"

license = "MIT"

keywords = [ "xmpp" ]

preferred_target = "native"

description = "An XMPP client library for MoonBit"

import {
  "moonbit-community/XMLParser@0.2.6",
  "moonbit-community/unicode@0.5.2",
  "moonbitlang/async@0.22.4",
  "moonbitlang/x@0.5.5",
}
