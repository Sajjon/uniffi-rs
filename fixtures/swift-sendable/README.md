# Test `Sendable`

Swift's protocol [`Sendable`](https://developer.apple.com/documentation/swift/sendable) is used to mark a type whose values can safely be passed across concurrency domains by copying.

In Swift 6 it is an error to try to pass a Non-Sendable value across concurrency domains.

If UniFFI Swift configuration `sendable_value_types: true` is not declared, Unifii developers need to mark all Swift `struct`s and `enum`s as `@unchecked Sendable {}`, to be used in concurrent contexts.