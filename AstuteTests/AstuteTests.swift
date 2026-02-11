//
//  AstuteTests.swift
//  AstuteTests
//
//  Created by David Armitage on 2/5/26.
//

import XCTest
@testable import Astute

final class AstuteTests: XCTestCase {

    func testExample() async throws {
        // Write your test here and use APIs like `XCTAssert(...)` to check expected conditions.
        XCTAssertTrue(true)
    }
    
    func testConversationCreation() async throws {
        let conversation = Conversation()
        XCTAssertEqual(conversation.title, "New Conversation")
        XCTAssertTrue(conversation.messages.isEmpty)
    }

}
