//
//  TaskSelectTests.swift
//  TaskSelectTests
//
//  Created by Klajd Deda on 9/14/22.
//

import XCTest
import Log4swift
import TaskSelect

@MainActor
final class TaskSelectTests: XCTestCase {
    // the task we want to succeed
    // true is taska, false is taskb
    var choice: Bool = false {
        didSet {
            // emulate some random task durations
            let durationa = UInt64.random(in: 150 ... 250)
            let durationb = UInt64.random(in: 50 ... 150)
            let maxDuration = max(durationa, durationb)
            let minDuration = min(durationa, durationb)
            
            self.values = [12, 21]
            self.timeouts = [(choice ? minDuration : maxDuration), (choice ? maxDuration : minDuration)]
            self.taska = Task<Int, Error> {
                // emulate some work
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * timeouts[0])
                try Task.checkCancellation()
                return values[0]
            }
            self.taskb = Task<Int, Error> {
                // emulate some work
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * timeouts[1])
                try Task.checkCancellation()
                return values[1]
            }
        }
    }
    var values: [Int] = []
    // we will bake in which task will complete first
    var timeouts: [UInt64] = []
    var taska: Task<Int, Error>!
    var taskb: Task<Int, Error>!

    override func setUp() async throws {
        // make sure we are logging to the console
        Log4swiftConfig.configureLogs(defaultLogFile: nil, lock: "IDDLogLock")
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

    /**
     Define 2 tasks such that we know which task will complete first
     We randomly decide which task will complete first.
     
     Construct the 'Task.select' and asert that it returns the value we expect.
     */
    func testTaskSelect() async throws {
        let expectation = self.expectation(description: "await")
        self.choice = Bool.random()
        let expectedValue = values[choice ? 0 : 1]

        Log4swift[Self.self].info("---------------------")
        Log4swift[Self.self].info("starting with the expectation to get: \(expectedValue) from: \(choice ? "taska" : "taskb")")
        Log4swift[Self.self].info("taska.duration: \(self.timeouts[0]) taskb.duration: \(self.timeouts[1])")

        // testing ...
        let test = Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let theSelectTask = await Task<Int, Error>.select(self.taska, self.taskb)
                    let TaskSelect = try await theSelectTask.value

                    Log4swift[Self.self].info("got: \(TaskSelect)")
                    XCTAssertEqual(TaskSelect, expectedValue)
                    expectation.fulfill()
                }
            }
        }
        _ = await test.value
        
        self.wait(for: [expectation], timeout: 1)
        Log4swift[Self.self].info("completed")
    }

    /**
     Define 2 tasks such that they take a bit to complete.
     
     Construct the 'Task.select' and asert that after we canceled it both children are also canceled.
     */
    func testSelectCancellation() async throws {
        let expectation = self.expectation(description: "await")
        self.choice = Bool.random()
        
        Log4swift[Self.self].info("---------------------")
        Log4swift[Self.self].info("both children should canceled")

        let theSelectTask = Task<Int, Error>.select(taska, taskb)
        theSelectTask.cancel()
        do {
            _ = try await theSelectTask.value
        } catch {
            Log4swift[Self.self].info("theSelectTask was canceled")
            expectation.fulfill()
        }
        
        XCTAssertEqual(taska.isCancelled, true)
        XCTAssertEqual(taskb.isCancelled, true)

        self.wait(for: [expectation], timeout: 1)
        Log4swift[Self.self].info("completed")
    }

    /**
     Define 2 tasks such that they take a bit to complete.

     Construct the 'Task.select' and asert that if i cancel both children the select fails.
     */
    func testBothChildrenCancellation() async throws {
        let expectation = self.expectation(description: "await")
        self.choice = Bool.random()

        Log4swift[Self.self].info("---------------------")
        Log4swift[Self.self].info("the select task will fail")

        // testing ...
        let test = Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let theSelectTask = await Task<Int, Error>.select(self.taska, self.taskb)
                    
                    do {
                        _ = try await theSelectTask.value
                    } catch {
                        let isCanceled: Bool = {
                            guard let error = error as? TaskSelectError,
                                  error == TaskSelectError.canceled
                            else { return false }
                            return true
                        }()
                        XCTAssertEqual(isCanceled, true)
                        expectation.fulfill()
                    }
                }
                group.addTask {
                    await self.taska.cancel()
                    await self.taskb.cancel()
                }
            }
        }
        _ = await test.value
        
        self.wait(for: [expectation], timeout: 1)
        Log4swift[Self.self].info("completed")
    }

}
