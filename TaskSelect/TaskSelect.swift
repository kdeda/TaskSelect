//
//  TaskSelect.swift
//  TaskSelect
//
//  Created by Klajd Deda on 9/14/22.
//

import Foundation
import Log4swift

public enum TaskSelectError: Error {
    case canceled
    case noValueReceived
}

public final actor TaskSelectActor<Value: Sendable> {
    private var values = [Int: Value]()
    private var cancelationCount = 0

    public init() {
    }

    /// Overwrite the isolated value with a new value.
    ///
    /// - Parameter newValue: The value to replace the current isolated value with.
    public func setValue1(_ newValue: Value) {
        self.values[1] = newValue
    }
    
    /// Overwrite the isolated value with a new value.
    ///
    /// - Parameter newValue: The value to replace the current isolated value with.
    public func setValue2(_ newValue: Value) {
        self.values[2] = newValue
    }
    
    public func incrementCancelationCount() {
        cancelationCount += 1
    }

    /// Return false if no value was received
    public var shouldCancel: Bool {
        cancelationCount == 2
    }
    
    /// - Parameter newValue: The value to replace the current isolated value with.
    public func TaskSelect() throws -> Value {
        if Task.isCancelled {
            throw TaskSelectError.canceled
        }
        
        if let value = values[1] {
            return value
        } else if let value = values[2] {
            return value
        }
        throw TaskSelectError.noValueReceived
    }

}

extension Task where Failure == Error {
    
    /**
     1. If task a completes first we cancel task b and return the task a result
     2. If task b completes first we cancel task a and return the task b result
     3. If the parent task, 'the select' is canceled, all child tasks are canceled
     4. If any of the child tasks fail the select fails
     
     withThrowingTaskGroup will give us the cancelation of children for free
     */
    public static func select<Success>(
        _ taska: Task<Success, Error>,
        _ taskb: Task<Success, Error>
    ) -> Task<Success, Error> {
        let returnValues = TaskSelectActor<Success>()
        
        let task = Task<Success, Error> {
            await withTaskCancellationHandler {
                Log4swift["TaskSelect"].info("we were cancelled and will cancel our children")
                taska.cancel()
                taskb.cancel()
            } operation: {
                _ = await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        Log4swift["TaskSelect"].info("waiting for taska ...")
                        do {
                            let value = try await taska.value
                            await returnValues.setValue1(value)
                            taskb.cancel()
                            Log4swift["TaskSelect"].info("get: \(value) from: taska")
                        } catch {
                            await returnValues.incrementCancelationCount()
                            Log4swift["TaskSelect"].info("taska was canceled")
                        }
                    }
                    group.addTask {
                        Log4swift["TaskSelect"].info("waiting for taskb ...")
                        do {
                            let value = try await taskb.value
                            await returnValues.setValue1(value)
                            taska.cancel()
                            Log4swift["TaskSelect"].info("get: \(value) from: taskb")
                        } catch {
                            await returnValues.incrementCancelationCount()
                            Log4swift["TaskSelect"].info("taskb was canceled")
                        }
                    }
                }
            }
            
            if await returnValues.shouldCancel {
                Log4swift["TaskSelect"].info("we should be canceled")
                // no need to do anything since we should exit the task anyway
                throw TaskSelectError.canceled
            }
            return try await returnValues.TaskSelect()
        }
        return task
    }
}
