import Testing
@testable import ScreenerKit

@Suite("Bounded screen-frame handoff")
struct LatestFrameSlotTests {
    @Test func slowConsumerReceivesNewestFrameThenFinalStaticFrame() {
        let slot = LatestFrameSlot<Int>()
        for frame in 0..<1_000 { slot.offer(frame) }
        #expect(slot.take() == 999)
        #expect(slot.take() == nil)
        slot.offer(1_000)
        slot.close()
        slot.offer(1_001)
        #expect(slot.take() == 1_000)
        #expect(slot.take() == nil)
        slot.close()
    }

    @Test func closeRejectsConcurrentLateCallbacks() async {
        let slot = LatestFrameSlot<Int>()
        await withTaskGroup(of: Void.self) { group in
            for frame in 0..<100 { group.addTask { slot.offer(frame) } }
            group.addTask { slot.close() }
        }
        _ = slot.take()
        slot.offer(999)
        #expect(slot.take() == nil)
    }
}
