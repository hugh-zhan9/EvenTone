import Foundation

// Standalone assertions let the same behavioral checks run with Command Line Tools,
// which ship neither XCTest nor Swift Testing. A failed expectation exits nonzero.
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    guard value else { fatalError("Expectation failed", file: file, line: line) }
}
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    expectTrue(!value, file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    expectTrue(value == nil, file: file, line: line)
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}
func expectEqual<T: BinaryFloatingPoint>(_ actual: T, _ expected: T, accuracy: T, file: StaticString = #file, line: UInt = #line) {
    guard abs(actual - expected) <= accuracy else { fatalError("Expected \(expected) ± \(accuracy), got \(actual)", file: file, line: line) }
}
func expectGreater<T: Comparable>(_ actual: T, _ bound: T, file: StaticString = #file, line: UInt = #line) {
    expectTrue(actual > bound, file: file, line: line)
}
func expectLess<T: Comparable>(_ actual: T, _ bound: T, file: StaticString = #file, line: UInt = #line) {
    expectTrue(actual < bound, file: file, line: line)
}
func expectAtMost<T: Comparable>(_ actual: T, _ bound: T, file: StaticString = #file, line: UInt = #line) {
    expectTrue(actual <= bound, file: file, line: line)
}
func unwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { fatalError("Unexpected nil", file: file, line: line) }
    return value
}
