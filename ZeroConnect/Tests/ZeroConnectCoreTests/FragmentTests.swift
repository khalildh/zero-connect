import Foundation
import Testing

@testable import ZeroConnectCore

@Suite("MessageFragmenter Tests")
struct FragmentTests {
    @Test("Small data is not fragmented")
    func noFragmentation() {
        let data = Data(repeating: 42, count: 100)
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(data, messageId: messageId)

        #expect(fragments.count == 1)
        #expect(fragments[0] == data, "Small data should be returned as-is")
    }

    @Test("Data at exact limit is not fragmented")
    func exactLimit() {
        let data = Data(repeating: 42, count: MessageFragmenter.maxLoRaPayload)
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(data, messageId: messageId)

        #expect(fragments.count == 1)
    }

    @Test("Large data is split into fragments")
    func fragmentLargeData() {
        let data = Data(repeating: 42, count: 500)
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(data, messageId: messageId)

        #expect(fragments.count > 1, "500 bytes should require multiple fragments")

        // Each fragment should fit in a LoRa packet
        for fragment in fragments {
            #expect(fragment.count <= MessageFragmenter.maxLoRaPayload)
        }
    }

    @Test("Fragments contain correct metadata")
    func fragmentMetadata() {
        let data = Data(repeating: 42, count: 500)
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(data, messageId: messageId)

        for (i, fragment) in fragments.enumerated() {
            let info = MessageFragmenter.fragmentInfo(fragment)
            #expect(info != nil, "Fragment should be parseable")
            #expect(info!.messageId == messageId, "Fragment should reference original message")
            #expect(info!.index == i, "Fragment index should match position")
            #expect(info!.total == fragments.count, "Total should match fragment count")
        }
    }

    @Test("Fragment reassembly produces original data")
    func reassembly() async {
        let original = Data((0..<500).map { UInt8($0 % 256) })
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(original, messageId: messageId)

        let collector = FragmentCollector()

        var result: Data?
        for fragment in fragments {
            result = await collector.addFragment(fragment)
        }

        #expect(result != nil, "Should reassemble after all fragments received")
        #expect(result == original, "Reassembled data should match original")
    }

    @Test("Reassembly works with out-of-order fragments")
    func outOfOrderReassembly() async {
        let original = Data((0..<500).map { UInt8($0 % 256) })
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(original, messageId: messageId)

        let collector = FragmentCollector()

        // Send in reverse order
        let reversed = fragments.reversed()
        var result: Data?
        for fragment in reversed {
            result = await collector.addFragment(fragment)
        }

        #expect(result != nil, "Should reassemble even out-of-order")
        #expect(result == original, "Reassembled data should match original")
    }

    @Test("Incomplete fragments return nil")
    func incompleteFragments() async {
        let original = Data(repeating: 42, count: 500)
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(original, messageId: messageId)
        #expect(fragments.count >= 2)

        let collector = FragmentCollector()

        // Only send the first fragment
        let result = await collector.addFragment(fragments[0])
        #expect(result == nil, "Single fragment should not produce reassembled data")
        #expect(await collector.pendingCount == 1)
    }

    @Test("isFragment detects multi-part fragments")
    func isFragmentDetection() {
        let data = Data(repeating: 42, count: 500)
        let messageId = UUID()
        let fragments = MessageFragmenter.fragment(data, messageId: messageId)

        for fragment in fragments {
            #expect(MessageFragmenter.isFragment(fragment) == true)
        }

        // Non-fragmented data should not be detected as fragment
        let small = Data(repeating: 0, count: 50)
        let noFrag = MessageFragmenter.fragment(small, messageId: UUID())
        #expect(MessageFragmenter.isFragment(noFrag[0]) == false)
    }

    @Test("Multiple messages can be reassembled independently")
    func multipleMessages() async {
        let data1 = Data((0..<400).map { UInt8($0 % 256) })
        let data2 = Data((0..<300).map { UInt8(($0 + 50) % 256) })
        let id1 = UUID()
        let id2 = UUID()

        let frags1 = MessageFragmenter.fragment(data1, messageId: id1)
        let frags2 = MessageFragmenter.fragment(data2, messageId: id2)

        let collector = FragmentCollector()

        // Interleave fragments from both messages
        var result1: Data?
        var result2: Data?

        for i in 0..<max(frags1.count, frags2.count) {
            if i < frags1.count {
                if let r = await collector.addFragment(frags1[i]) {
                    result1 = r
                }
            }
            if i < frags2.count {
                if let r = await collector.addFragment(frags2[i]) {
                    result2 = r
                }
            }
        }

        #expect(result1 == data1, "First message should reassemble correctly")
        #expect(result2 == data2, "Second message should reassemble correctly")
    }
}
