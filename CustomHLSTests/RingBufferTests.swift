import XCTest
@testable import CustomHLS

class RingBufferTests: XCTestCase {
    
    func testRingBufferEnqueueAndDequeue() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertFalse(buffer.isFull)
        
        // Enqueue elements
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertTrue(buffer.enqueue(3))
        
        XCTAssertTrue(buffer.isFull)
        XCTAssertFalse(buffer.isEmpty)
        
        // Dequeue elements
        XCTAssertEqual(buffer.dequeue(), 1)
        XCTAssertEqual(buffer.dequeue(), 2)
        XCTAssertEqual(buffer.dequeue(), 3)
        
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertFalse(buffer.isFull)
        XCTAssertNil(buffer.dequeue())
    }

    func testRingBufferWrapAround() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        // Enqueue elements
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertTrue(buffer.enqueue(3))
        
        // Dequeue one element to make space
        XCTAssertEqual(buffer.dequeue(), 1)
        
        // Enqueue another element, this should wrap around
        XCTAssertTrue(buffer.enqueue(4))
        
        // Check the internal order after wrap-around
        XCTAssertEqual(buffer.dequeue(), 2)
        XCTAssertEqual(buffer.dequeue(), 3)
        XCTAssertEqual(buffer.dequeue(), 4)
        
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRingBufferResize() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        // Enqueue more elements than the initial capacity to trigger resizing
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertTrue(buffer.enqueue(3))
        
        XCTAssertTrue(buffer.isFull)
        
        // This should trigger a resize
        XCTAssertTrue(buffer.enqueue(4))
        
        // The buffer should no longer be full after resizing
        XCTAssertFalse(buffer.isFull)
        
        // Dequeue all elements and check the order
        XCTAssertEqual(buffer.dequeue(), 1)
        XCTAssertEqual(buffer.dequeue(), 2)
        XCTAssertEqual(buffer.dequeue(), 3)
        XCTAssertEqual(buffer.dequeue(), 4)
        
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRingBufferFlush() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        // Enqueue elements
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertTrue(buffer.enqueue(3))
        
        // Flush the buffer
        buffer.flush()
        
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.dequeue())
        XCTAssertTrue(buffer.enqueue(4))
        XCTAssertEqual(buffer.dequeue(), 4)
    }

    func testRingBufferPeek() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        // Enqueue elements and peek
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertEqual(buffer.peek(), 1)
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertEqual(buffer.peek(), 1)
        
        // Dequeue an element and peek again
        XCTAssertEqual(buffer.dequeue(), 1)
        XCTAssertEqual(buffer.peek(), 2)
    }
    
    // Test repeated resize operations
    func testRepeatedResizes() {
        var buffer = RingBuffer<Int>(capacity: 2)
        
        // Enqueue elements to trigger multiple resizes
        for i in 1...10 {
            XCTAssertTrue(buffer.enqueue(i))
        }
        
        XCTAssertEqual(buffer.capacity, 16) // Resized twice: 2 -> 4 -> 8 -> 16
        XCTAssertEqual(buffer.count, 10)
        
        // Dequeue and verify all elements
        for i in 1...10 {
            XCTAssertEqual(buffer.dequeue(), i)
        }
        
        XCTAssertTrue(buffer.isEmpty)
    }

    // Test multiple wrap-arounds with resizing
    func testMultipleWrapArounds() {
        var buffer = RingBuffer<Int>(capacity: 4)
        
        // Fill the buffer to capacity and dequeue some elements
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertTrue(buffer.enqueue(3))
        XCTAssertTrue(buffer.enqueue(4))
        
        XCTAssertEqual(buffer.dequeue(), 1)
        XCTAssertEqual(buffer.dequeue(), 2)
        
        // Wrap around by adding new elements
        XCTAssertTrue(buffer.enqueue(5))
        XCTAssertTrue(buffer.enqueue(6))
        
        // The buffer is full, so it should resize when another element is added
        XCTAssertTrue(buffer.enqueue(7))  // Resizes to capacity 8
        
        // Dequeue all elements and verify the order is maintained
        XCTAssertEqual(buffer.dequeue(), 3)
        XCTAssertEqual(buffer.dequeue(), 4)
        XCTAssertEqual(buffer.dequeue(), 5)
        XCTAssertEqual(buffer.dequeue(), 6)
        XCTAssertEqual(buffer.dequeue(), 7)
        
        XCTAssertTrue(buffer.isEmpty)
    }
    
    // Test interleaving enqueue and dequeue operations with resizing
    func testInterleavedOperationsWithResizing() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        // Enqueue and dequeue operations interleaved
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertEqual(buffer.dequeue(), 1)
        
        XCTAssertTrue(buffer.enqueue(3))
        XCTAssertTrue(buffer.enqueue(4))  // Buffer is full now
        
        // Trigger a resize by adding another element
        XCTAssertTrue(buffer.enqueue(5))  // Resizes to capacity 6
        
        XCTAssertEqual(buffer.dequeue(), 2)
        XCTAssertEqual(buffer.dequeue(), 3)
        XCTAssertEqual(buffer.dequeue(), 4)
        XCTAssertEqual(buffer.dequeue(), 5)
        
        XCTAssertTrue(buffer.isEmpty)
    }

    // Test edge case: Dequeue and enqueue after several wrap-arounds
    func testEdgeCaseMultipleWrapArounds() {
        var buffer = RingBuffer<Int>(capacity: 3)
        
        // Enqueue 3 elements to fill the buffer
        XCTAssertTrue(buffer.enqueue(1))
        XCTAssertTrue(buffer.enqueue(2))
        XCTAssertTrue(buffer.enqueue(3))
        
        // Dequeue 2 elements, head should move forward
        XCTAssertEqual(buffer.dequeue(), 1)
        XCTAssertEqual(buffer.dequeue(), 2)
        
        // Enqueue 2 more elements (wrap around)
        XCTAssertTrue(buffer.enqueue(4))
        XCTAssertTrue(buffer.enqueue(5))
        
        // Dequeue 1 element and check consistency
        XCTAssertEqual(buffer.dequeue(), 3)
        
        // Enqueue another element to wrap around again
        XCTAssertTrue(buffer.enqueue(6))
        
        // Dequeue remaining elements
        XCTAssertEqual(buffer.dequeue(), 4)
        XCTAssertEqual(buffer.dequeue(), 5)
        XCTAssertEqual(buffer.dequeue(), 6)
        
        XCTAssertTrue(buffer.isEmpty)
    }

    // Test behavior after resizing with many enqueues and dequeues
    func testResizeWithManyEnqueueDequeue() {
        var buffer = RingBuffer<Int>(capacity: 4)
        
        // Fill the buffer and dequeue some elements
        for i in 1...4 {
            XCTAssertTrue(buffer.enqueue(i))
        }
        XCTAssertEqual(buffer.dequeue(), 1)
        XCTAssertEqual(buffer.dequeue(), 2)
        
        // Add more elements and trigger resizing
        XCTAssertTrue(buffer.enqueue(5))
        XCTAssertTrue(buffer.enqueue(6))
        XCTAssertTrue(buffer.enqueue(7))  // This should trigger resize
        
        XCTAssertEqual(buffer.capacity, 8)
        
        // Dequeue remaining elements and ensure correct order
        XCTAssertEqual(buffer.dequeue(), 3)
        XCTAssertEqual(buffer.dequeue(), 4)
        XCTAssertEqual(buffer.dequeue(), 5)
        XCTAssertEqual(buffer.dequeue(), 6)
        XCTAssertEqual(buffer.dequeue(), 7)
        
        XCTAssertTrue(buffer.isEmpty)
    }
}
