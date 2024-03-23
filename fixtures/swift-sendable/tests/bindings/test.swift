// Regression test for https://github.com/mozilla/uniffi-rs/issues/1312
//
// Really this can be detected at compile time:
// We didn't apply the same `omit_argument_labels` configuration to callbacks,
// leading to a compilation error.
// To make sure everything gets called right though we write a full test here.

import swift_sendable

final actor MyActor {
  private var value: any Sendable
  init() {
    self.value = false
  }
  func takeSendable(_ value: any Sendable) {
    self.value = value
  }
}

func test_sendable() async {

  let myActor = MyActor()
  func doTest(_ value: any Sendable) async {
    await myActor.takeSendable(value)
  }

  let recordWithoutObjects = RecordWithoutObjects(
    string: "Foo",
    vec: [true],
    u: 42,
    map: ["bar": [512, 2024]]
  )

  // Test trivial primitives which are Sendable
  await doTest(true)
  await doTest("foo")
  await doTest(1337)
  await doTest(recordWithoutObjects)  // marked Sendable by UniFFI!

  func testEnum(_ `enum`: EnumWithoutObjects) async {
    await doTest(`enum`)
  }
  await testEnum(.recordWithoutObjects(recordWithoutObjects))
  await testEnum(.string("bar"))
  await testEnum(.bool(true))
  await testEnum(.vec([1024, 1337]))

  /* Next lines should fail to compile if strict concurrency is enabled and if warnings treated as errors. */
//   await doTest(MyObject(string: "bad"))
//   await doTest(RecordWithObject(string: "Foo", obj: MyObject(string: "bad")))
//   await doTest(EnumWithIndirectObject.recordWithObjects(RecordWithObject(string: "foo", obj: MyObject(string: "bad"))))
}

func test() async {
  await test_sendable()
}

await test()
