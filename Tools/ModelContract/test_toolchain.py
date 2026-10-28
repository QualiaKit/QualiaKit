import unittest

from reference_inference import supported_toolchain


class ToolchainTests(unittest.TestCase):
    def test_only_declared_complete_toolchain_tuples_are_accepted(self):
        self.assertTrue(supported_toolchain("Apple Swift version 6.3.3 (swiftlang-test)", "Xcode 26.6", "3520.5.1"))
        self.assertTrue(supported_toolchain("swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-test)", "Xcode 27.1", "3600.25.1"))
        for swift, xcode, compiler in [
            ("Apple Swift version 6.40", "Xcode 27.1", "3600.25.1"),
            ("Apple Swift version 6.4", "Xcode 26.6", "3600.25.1"),
            ("Apple Swift version 6.4", "Xcode 27.1", "3520.5.1"),
            ("unrecognized compiler", "Xcode 27.1", "3600.25.1"),
        ]:
            self.assertFalse(supported_toolchain(swift, xcode, compiler))


if __name__ == "__main__":
    unittest.main()
