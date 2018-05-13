//
//  Nightscout.swift
//  NightscoutKit
//
//  Created by Michael Pangburn on 2/16/18.
//  Copyright © 2018 Michael Pangburn. All rights reserved.
//

import Foundation


/// The primary interface for interacting with the Nightscout API.
/// This class performs operations such as:
/// - fetching and uploading blood glucose entries
/// - fetching, uploading, updating, and deleting treatments
/// - fetching, uploading, updating, and deleting profile records
/// - fetching device statuses
/// - fetching the site status and settings
public final class Nightscout {
    /// The router for configuring URL requests.
    private let router: NightscoutRouter

    /// The observers responding to operations performed by this `Nightscout` instance,
    /// boxed to hold references weakly.
    private let _observers: ThreadSafe<[ObjectIdentifier: NightscoutObserverBox]>

    /// The URL sessions for accessing the API endpoints of this `Nightscout` instance.
    private let sessions: Sessions

    /// The queues for asynchronously performing concurrent operations for this `Nightscout` instance.
    private let queues: Queues

    /// The credentials for accessing Nightscout, including the site URL and API secret.
    public var credentials: NightscoutCredentials {
        return router.credentials
    }

    /// Creates a new `Nightscout` instance for interacting with a Nightscout site.
    /// - Parameter credentials: The verified credentials for accessing the Nightscout site.
    ///                          If `credentials.apiSecret` is `nil`, upload, update, and delete operations will fail.
    /// - Returns: A new `Nightscout` instance for interacting with a Nightscout site.
    public init(credentials: NightscoutCredentials) {
        self.router = NightscoutRouter(credentials: credentials)
        self._observers = ThreadSafe([:])
        self.sessions = Sessions()
        self.queues = Queues()
    }
}

// MARK: - Observers

extension Nightscout {
    /// Adds the observer to this `Nightscout` instance.
    ///
    /// **Note:** Observers are notified of `Nightscout` operations concurrently.
    /// The order in which observers are added is not reflective
    /// of the order in which they will be notified.
    /// - Parameter observer: The object to begin observing this `Nightscout` instance.
    public func addObserver(_ observer: NightscoutObserver) {
        _observers.atomically { observers in
            let id = ObjectIdentifier(observer)
            observers[id] = NightscoutObserverBox(observer)
        }
    }

    /// Adds the observers to this `Nightscout` instance.
    ///
    /// **Note:** Observers are notified of `Nightscout` operations concurrently.
    /// The order in which observers are added is not reflective
    /// of the order in which they will be notified.
    /// - Parameter observers: The objects to begin observing this `Nightscout` instance.
    public func addObservers(_ observers: [NightscoutObserver]) {
        _observers.atomically { observersDictionary in
            for observer in observers {
                let id = ObjectIdentifier(observer)
                observersDictionary[id] = NightscoutObserverBox(observer)
            }
        }
    }

    /// Adds the observers to this `Nightscout` instance.
    ///
    /// **Note:** Observers are notified of `Nightscout` operations concurrently.
    /// The order in which observers are added is not reflective
    /// of the order in which they will be notified.
    /// - Parameter observers: The objects to begin observing this `Nightscout` instance.
    public func addObservers(_ observers: NightscoutObserver...) {
        addObservers(observers)
    }

    /// Removes the observer from this `Nightscout` instance.
    ///
    /// If the observer is not currently observing this `Nightscout` instance, this method does nothing.
    /// - Parameter observer: The object to stop observing this `Nightscout` instance.
    public func removeObserver(_ observer: NightscoutObserver) {
        _observers.atomically { observers in
            let id = ObjectIdentifier(observer)
            observers.removeValue(forKey: id)
        }
    }

    /// Removes all observers from this `Nightscout` instance.
    public func removeAllObservers() {
        _observers.atomically { $0.removeAll() }
    }

    internal var observers: [NightscoutObserver] {
        return _observers.value.values.compactMap { $0.observer }
    }
}

// MARK: - API Access

extension Nightscout {
    private typealias QueryItem = NightscoutQueryItem
    private typealias APIEndpoint = NightscoutAPIEndpoint

    private struct Sessions {
        let settingsSession = URLSession(configuration: .default)
        let entriesSession = URLSession(configuration: .default)
        let treatmentsSession = URLSession(configuration: .default)
        let profilesSession = URLSession(configuration: .default)
        let deviceStatusSession = URLSession(configuration: .default)
        let authorizationSession = URLSession(configuration: .default)

        func urlSession(for endpoint: APIEndpoint) -> URLSession {
            switch endpoint {
            case .entries:
                return entriesSession
            case .treatments:
                return treatmentsSession
            case .profiles:
                return profilesSession
            case .status:
                return settingsSession
            case .deviceStatus:
                return deviceStatusSession
            case .authorization:
                return authorizationSession
            }
        }
    }

    private struct Queues {
        let treatmentsQueue = DispatchQueue(label: "com.mpangburn.nightscoutkit.treatments")
        let profilesQueue = DispatchQueue(label: "com.mpangburn.nightscoutkit.profiles")
        let snapshotQueue = DispatchQueue(label: "com.mpangburn.nightscoutkit.snapshot")
        let defaultQueue = DispatchQueue(label: "com.mpangburn.nightscoutkit.default")

        func dispatchQueue(for endpoint: APIEndpoint) -> DispatchQueue {
            switch endpoint {
            case .treatments:
                return treatmentsQueue
            case .profiles:
                return profilesQueue
            default:
                return defaultQueue // unused, only treatments + profiles support update/delete,
                                    // which is where this method is used
            }
        }
    }
}

// MARK: - Fetching

extension Nightscout {
    /// Takes a snapshot of the current Nightscout site.
    /// - Parameter recentBloodGlucoseEntryCount: The number of recent blood glucose entries to fetch. Defaults to 10.
    /// - Parameter recentTreatmentCount: The number of recent treatments to fetch. Defaults to 10.
    /// - Parameter recentDeviceStatusCount: The number of recent device statuses to fetch. Defaults to 10.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func snapshot(recentBloodGlucoseEntryCount: Int = 10, recentTreatmentCount: Int = 10, recentDeviceStatusCount: Int = 10,
                         completion: @escaping (_ result: NightscoutResult<NightscoutSnapshot>) -> Void) {
        let timestamp = Date()
        var status: NightscoutStatus?
        var deviceStatuses: [NightscoutDeviceStatus] = []
        var entries: [NightscoutEntry] = []
        var treatments: [NightscoutTreatment] = []
        var profileRecords: [NightscoutProfileRecord] = []
        let error: ThreadSafe<NightscoutError?> = ThreadSafe(nil)

        let snapshotGroup = DispatchGroup()

        snapshotGroup.enter()
        fetchStatus { result in
            switch result {
            case .success(let fetchedStatus):
                status = fetchedStatus
            case .failure(let err):
                error.atomicallyAssign(to: err)
            }
            snapshotGroup.leave()
        }

        snapshotGroup.enter()
        fetchMostRecentDeviceStatuses(count: recentDeviceStatusCount) { result in
            switch result {
            case .success(let fetchedDeviceStatuses):
                deviceStatuses = fetchedDeviceStatuses
            case .failure(let err):
                error.atomicallyAssign(to: err)
            }
            snapshotGroup.leave()
        }

        snapshotGroup.enter()
        fetchProfileRecords { result in
            switch result {
            case .success(let fetchedProfileRecords):
                profileRecords = fetchedProfileRecords
            case .failure(let err):
                error.atomicallyAssign(to: err)
            }
            snapshotGroup.leave()
        }

        snapshotGroup.enter()
        fetchMostRecentEntries(count: recentBloodGlucoseEntryCount) { result in
            switch result {
            case .success(let fetchedBloodGlucoseEntries):
                entries = fetchedBloodGlucoseEntries
            case .failure(let err):
                error.atomicallyAssign(to: err)
            }
            snapshotGroup.leave()
        }

        snapshotGroup.enter()
        fetchMostRecentTreatments(count: recentTreatmentCount) { result in
            switch result {
            case .success(let fetchedTreatments):
                treatments = fetchedTreatments
            case .failure(let err):
                error.atomicallyAssign(to: err)
            }
            snapshotGroup.leave()
        }

        snapshotGroup.notify(queue: queues.snapshotQueue) {
            // There's a race condition with errors here, but if any fetch request fails, we'll report an error--it doesn't matter which.
            guard error.value == nil else {
                completion(.failure(error.value!))
                return
            }

            let snapshot = NightscoutSnapshot(timestamp: timestamp, status: status!, entries: entries,
                                              treatments: treatments, profileRecords: profileRecords, deviceStatuses: deviceStatuses)
            completion(.success(snapshot))
        }
    }

    /// Fetches the status of the Nightscout site.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchStatus(completion: ((_ result: NightscoutResult<NightscoutStatus>) -> Void)? = nil) {
        fetch(from: .status) { (result: NightscoutResult<NightscoutStatus>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, status in observer.nightscout(nightscout, didFetchStatus: status) } }
            )
            completion?(result)
        }
    }

    /// Fetches the most recent blood glucose entries.
    /// - Parameter count: The number of recent blood glucose entries to fetch. Defaults to 10.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchMostRecentEntries(count: Int = 10,
                                       completion: ((_ result: NightscoutResult<[NightscoutEntry]>) -> Void)? = nil) {
        let queryItems: [QueryItem] = [.count(count)]
        fetch(from: .entries, queryItems: queryItems) { (result: NightscoutResult<[NightscoutEntry]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, entries in observer.nightscout(nightscout, didFetchEntries: entries) } }
            )
            completion?(result)
        }
    }

    /// Fetches the blood glucose entries from within the specified `DateInterval`.
    /// - Parameter interval: The interval from which blood glucose entries should be fetched.
    /// - Parameter maxCount: The maximum number of blood glucose entries to fetch. Defaults to `2 ** 31`, where `**` is exponentiation.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchEntries(fromInterval interval: DateInterval, maxCount: Int = 2 << 31,
                             completion: ((_ result: NightscoutResult<[NightscoutEntry]>) -> Void)? = nil) {
        let queryItems = QueryItem.entryDates(from: interval).appending(.count(maxCount))
        fetch(from: .entries, queryItems: queryItems) { (result: NightscoutResult<[NightscoutEntry]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, entries in observer.nightscout(nightscout, didFetchEntries: entries) } }
            )
            completion?(result)
        }
    }

    /// Fetches the most recent treatments.
    /// - Parameter eventKind: The event kind to match. If this argument is `nil`, all event kinds are included. Defaults to `nil`.
    /// - Parameter count: The number of recent treatments to fetch. Defaults to 10.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchMostRecentTreatments(matching eventKind: NightscoutTreatment.EventType.Kind? = nil, count: Int = 10,
                                          completion: ((_ result: NightscoutResult<[NightscoutTreatment]>) -> Void)? = nil) {
        var queryItems: [QueryItem] = [.count(count)]
        eventKind.map(QueryItem.treatmentEventType(matching:)).map { queryItems.append($0) }
        fetch(from: .treatments, queryItems: queryItems) { (result: NightscoutResult<[NightscoutTreatment]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, treatments in observer.nightscout(nightscout, didFetchTreatments: treatments) } }
            )
            completion?(result)
        }
    }

    /// Fetches the treatments meeting the given specifications.
    /// - Parameter eventKind: The event kind to match. If this argument is `nil`, all event kinds are included. Defaults to `nil`.
    /// - Parameter interval: The interval from which treatments should be fetched.
    /// - Parameter maxCount: The maximum number of treatments to fetch. Defaults to `2 ** 31`, where `**` is exponentiation.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchTreatments(matching eventKind: NightscoutTreatment.EventType.Kind? = nil, fromInterval interval: DateInterval, maxCount: Int = 2 << 31,
                                completion: ((_ result: NightscoutResult<[NightscoutTreatment]>) -> Void)? = nil) {
        var queryItems = QueryItem.treatmentDates(from: interval).appending(.count(maxCount))
        eventKind.map(QueryItem.treatmentEventType(matching:)).map { queryItems.append($0) }
        fetch(from: .treatments, queryItems: queryItems) { (result: NightscoutResult<[NightscoutTreatment]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, treatments in observer.nightscout(nightscout, didFetchTreatments: treatments) } }
            )
            completion?(result)
        }
    }

    /// Fetches the profile records.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchProfileRecords(completion: ((_ result: NightscoutResult<[NightscoutProfileRecord]>) -> Void)? = nil) {
        fetch(from: .profiles) { (result: NightscoutResult<[NightscoutProfileRecord]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, records in observer.nightscout(nightscout, didFetchProfileRecords: records) } }
            )
            completion?(result)
        }
    }

    /// Fetches the most recent device statuses.
    /// - Parameter count: The number of recent device statuses to fetch. Defaults to 10.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchMostRecentDeviceStatuses(count: Int = 10,
                                              completion: ((_ result: NightscoutResult<[NightscoutDeviceStatus]>) -> Void)? = nil) {
        let queryItems: [QueryItem] = [.count(count)]
        fetch(from: .deviceStatus, queryItems: queryItems) { (result: NightscoutResult<[NightscoutDeviceStatus]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, deviceStatuses in observer.nightscout(nightscout, didFetchDeviceStatuses: deviceStatuses) } }
            )
            completion?(result)
        }
    }

    /// Fetches the device statuses from within the specified `DateInterval`.
    /// - Parameter interval: The interval from which device statuses should be fetched.
    /// - Parameter maxCount: The maximum number of device statuses to fetch. Defaults to `2 ** 31`, where `**` is exponentiation.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation.
    public func fetchDeviceStatuses(fromInterval interval: DateInterval, maxCount: Int = 2 << 31,
                                    completion: ((_ result: NightscoutResult<[NightscoutDeviceStatus]>) -> Void)? = nil) {
        let queryItems = QueryItem.deviceStatusDates(from: interval) + [.count(maxCount)]
        fetch(from: .deviceStatus, queryItems: queryItems) { (result: NightscoutResult<[NightscoutDeviceStatus]>) in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, deviceStatuses in observer.nightscout(nightscout, didFetchDeviceStatuses: deviceStatuses) } }
            )
            completion?(result)
        }
    }
}

extension Nightscout {
    private func fetchData(from endpoint: APIEndpoint, with request: URLRequest,
                           completion: @escaping (NightscoutResult<Data>) -> Void) {
        let session = sessions.urlSession(for: endpoint)
        let task = session.dataTask(with: request) { data, response, error in
            guard error == nil else {
                completion(.failure(.fetchError(error!)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.notAnHTTPURLResponse))
                return
            }

            guard let data = data else {
                fatalError("The data task produced no error, but also returned no data. These states are mutually exclusive.")
            }

            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 401:
                    completion(.failure(.unauthorized))
                default:
                    let body = String(data: data, encoding: .utf8)!
                    completion(.failure(.httpError(statusCode: httpResponse.statusCode, body: body)))
                }
                return
            }

            completion(.success(data))
        }

        task.resume()
    }

    private func fetchData(from endpoint: APIEndpoint, queryItems: [QueryItem],
                           completion: @escaping (NightscoutResult<Data>) -> Void) {
        guard let request = router.configureURLRequest(for: endpoint, queryItems: queryItems, httpMethod: .get) else {
            completion(.failure(.invalidURL))
            return
        }

        fetchData(from: endpoint, with: request, completion: completion)
    }

    private func fetch<Response: JSONParseable>(from endpoint: APIEndpoint, queryItems: [QueryItem] = [], completion: @escaping (NightscoutResult<Response>) -> Void) {
        fetchData(from: endpoint, queryItems: queryItems) { result in
            switch result {
            case .success(let data):
                do {
                    guard let parsed = try Response.parse(fromData: data) else {
                        completion(.failure(.dataParsingFailure(data)))
                        return
                    }
                    completion(.success(parsed))
                } catch {
                    completion(.failure(.jsonParsingError(error)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Uploading

extension Nightscout {
    /// Describes a response to a Nightscout post request.
    /// A successful result contains a tuple containing the successfully uploaded items and the rejected items.
    public typealias PostResponse<Payload: Hashable> = NightscoutResult<(uploadedItems: Set<Payload>, rejectedItems: Set<Payload>)>

    /// A tuple containing the set of items successfully processed by an operation and the set of rejections.
    public typealias OperationResult<Payload: Hashable> = (processedItems: Set<Payload>, rejections: Set<Rejection<Payload>>)

    /// Describes the item for which an operation failed and the error produced.
    public struct Rejection<Payload: Hashable>: Hashable {
        /// The item for which the operation failed.
        public let item: Payload

        /// The error that produced the operation failure.
        public let error: NightscoutError

        public static func == (lhs: Rejection, rhs: Rejection) -> Bool {
            return lhs.item == rhs.item // ignore the error
        }

        public var hashValue: Int {
            return item.hashValue // ignore the error
        }
    }

    /// Verifies that the instance is authorized to upload, update, and delete entities.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter error: The error that occurred in verifying authorization. `nil` indicates success.
    public func verifyAuthorization(completion: ((_ error: NightscoutError?) -> Void)? = nil) {
        guard credentials.apiSecret != nil else {
            completion?(.missingAPISecret)
            return
        }

        guard let request = router.configureURLRequest(for: .authorization) else {
            completion?(.invalidURL)
            return
        }

        fetchData(from: .authorization, with: request) { result in
            self.observers.notify(
                for: result, from: self,
                ifSuccess: { observer in { nightscout, _ in observer.nightscoutDidVerifyAuthorization(nightscout) } }
            )
            completion?(result.error)
        }
    }

    /// Uploads the blood glucose entries.
    /// - Parameter entries: The blood glucose entries to upload.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation. A successful result contains a tuple containing the successfully uploaded entries and the rejected entries.
    public func uploadEntries(_ entries: [NightscoutEntry],
                              completion: ((_ result: PostResponse<NightscoutEntry>) -> Void)? = nil) {
        post(entries, to: .entries) { (result: PostResponse<NightscoutEntry>) in
            self.observers.notify(
                for: result, from: self,
                withSuccesses: { observer in { nightscout, entries in observer.nightscout(nightscout, didUploadEntries: entries) } },
                withRejections: { observer in { nightscout, entries in observer.nightscout(nightscout, didFailToUploadEntries: entries) } },
                ifError: { observer in observer.nightscout(self, didFailToUploadEntries: Set(entries)) }
            )
            completion?(result)
        }
    }

    // FIXME: entry deletion fails--but why?
    /* public */ func deleteEntries(_ entries: [NightscoutEntry],
                                    completion: @escaping (_ operationResult: OperationResult<NightscoutEntry>) -> Void) {
        // TODO: observer API once this is fixed
        delete(entries, from: .entries, completion: completion)
    }

    /// Uploads the treatments.
    /// - Parameter treatments: The treatments to upload.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation. A successful result contains a tuple containing the successfully uploaded treatments and the rejected treatments.
    public func uploadTreatments(_ treatments: [NightscoutTreatment],
                                 completion: ((_ result: PostResponse<NightscoutTreatment>) -> Void)? = nil) {
        post(treatments, to: .treatments) { (result: PostResponse<NightscoutTreatment>) in
            self.observers.notify(
                for: result, from: self,
                withSuccesses: { observer in { nightscout, treatments in observer.nightscout(nightscout, didUploadTreatments: treatments) } },
                withRejections: { observer in { nightscout, treatments in observer.nightscout(nightscout, didFailToUploadTreatments: treatments) } },
                ifError: { observer in observer.nightscout(self, didFailToUploadTreatments: Set(treatments)) }
            )
            completion?(result)
        }
    }

    /// Updates the treatments.
    /// If treatment dates are modified, Nightscout will post the treatments as duplicates. In these cases, it is recommended to delete these treatments
    /// and reupload them rather than update them.
    /// - Parameter treatments: The treatments to update.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter operationResult: The result of the operation, which contains both the successfully updated treatments and the rejections.
    public func updateTreatments(_ treatments: [NightscoutTreatment],
                                 completion: ((_ operationResult: OperationResult<NightscoutTreatment>) -> Void)? = nil) {
        put(treatments, to: .treatments) { (operationResult: OperationResult<NightscoutTreatment>) in
            self.observers.notify(
                for: operationResult, from: self,
                withSuccesses: { observer in { nightscout, treatments in observer.nightscout(nightscout, didUpdateTreatments: treatments) } },
                withRejections: { observer in { nightscout, treatments in observer.nightscout(nightscout, didFailToUpdateTreatments: treatments) } }
            )
            completion?(operationResult)
        }
    }

    /// Deletes the treatments.
    /// - Parameter treatments: The treatments to delete.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter operationResult: The result of the operation, which contains both the successfully deleted treatments and the rejections.
    public func deleteTreatments(_ treatments: [NightscoutTreatment],
                                 completion: ((_ operationResult: OperationResult<NightscoutTreatment>) -> Void)? = nil) {
        delete(treatments, from: .treatments) { (operationResult: OperationResult<NightscoutTreatment>) in
            self.observers.notify(
                for: operationResult, from: self,
                withSuccesses: { observer in { nightscout, treatments in observer.nightscout(nightscout, didDeleteTreatments: treatments) } },
                withRejections: { observer in { nightscout, treatments in observer.nightscout(nightscout, didFailToDeleteTreatments: treatments) } }
            )
            completion?(operationResult)
        }
    }

    /// Uploads the profile records.
    /// - Parameter records: The profile records to upload.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter result: The result of the operation. A successful result contains a tuple containing the successfully uploaded records and the rejected records.
    public func uploadProfileRecords(_ records: [NightscoutProfileRecord],
                                     completion: ((_ result: PostResponse<NightscoutProfileRecord>) -> Void)? = nil) {
        post(records, to: .profiles) { (result: PostResponse<NightscoutProfileRecord>) in
            self.observers.notify(
                for: result, from: self,
                withSuccesses: { observer in { nightscout, records in observer.nightscout(nightscout, didUploadProfileRecords: records) } },
                withRejections: { observer in { nightscout, records in observer.nightscout(nightscout, didFailToUploadProfileRecords: records) } },
                ifError: { observer in observer.nightscout(self, didFailToUploadProfileRecords: Set(records)) }
            )
            completion?(result)
        }
    }

    /// Updates the profile records.
    /// If profile record dates are modified, Nightscout will post the profile records as duplicates. In these cases, it is recommended to delete these records
    /// and reupload them rather than update them.
    /// - Parameter records: The profile records to update.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter operationResult: The result of the operation, which contains both the successfully updated records and the rejections.
    public func updateProfileRecords(_ records: [NightscoutProfileRecord],
                                     completion: ((_ operationResult: OperationResult<NightscoutProfileRecord>) -> Void)? = nil) {
        put(records, to: .profiles) { (operationResult: OperationResult<NightscoutProfileRecord>) in
            self.observers.notify(
                for: operationResult, from: self,
                withSuccesses: { observer in { nightscout, records in observer.nightscout(nightscout, didUpdateProfileRecords: records) } },
                withRejections: { observer in { nightscout, records in observer.nightscout(nightscout, didFailToUpdateProfileRecords: records) } }
            )
            completion?(operationResult)
        }
    }

    /// Deletes the profile records.
    /// - Parameter records: The profile records to delete.
    /// - Parameter completion: The completion handler to be called upon completing the operation.
    ///                         Observers will be notified of the result of this operation before `completion` is invoked.
    /// - Parameter operationResult: The result of the operation, which contains both the successfully deleted records and the rejections.
    public func deleteProfileRecords(_ records: [NightscoutProfileRecord],
                                     completion: ((_ operationResult: OperationResult<NightscoutProfileRecord>) -> Void)? = nil) {
        delete(records, from: .profiles) { (operationResult: OperationResult<NightscoutProfileRecord>) in
            self.observers.notify(
                for: operationResult, from: self,
                withSuccesses: { observer in { nightscout, records in observer.nightscout(nightscout, didDeleteProfileRecords: records) } },
                withRejections: { observer in { nightscout, records in observer.nightscout(nightscout, didFailToDeleteProfileRecords: records) } }
            )
            completion?(operationResult)
        }
    }
}

extension Nightscout {
    private func uploadData(_ data: Data, to endpoint: APIEndpoint, with request: URLRequest,
                            completion: @escaping (NightscoutResult<Data>) -> Void) {
        let session = sessions.urlSession(for: endpoint)
        let task = session.uploadTask(with: request, from: data) { data, response, error in
            guard error == nil else {
                completion(.failure(.uploadError(error!)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.notAnHTTPURLResponse))
                return
            }

            guard let data = data else {
                fatalError("The data task produced no error, but also returned no data. These states are mutually exclusive.")
            }

            guard httpResponse.statusCode == 200 else {
                switch httpResponse.statusCode {
                case 401:
                    completion(.failure(.unauthorized))
                default:
                    let body = String(data: data, encoding: .utf8)!
                    completion(.failure(.httpError(statusCode: httpResponse.statusCode, body: body)))
                }
                return
            }

            completion(.success(data))
        }

        task.resume()
    }

    private func upload<Payload: JSONRepresentable, Response: JSONParseable>(_ item: Payload, to endpoint: APIEndpoint, httpMethod: HTTPMethod,
                                                                             completion: @escaping (NightscoutResult<Response>) -> Void) {
        guard credentials.apiSecret != nil else {
            completion(.failure(.missingAPISecret))
            return
        }

        guard let request = router.configureURLRequest(for: endpoint, httpMethod: httpMethod) else {
            completion(.failure(.invalidURL))
            return
        }

        let data: Data
        do {
            data = try item.data()
        } catch {
            completion(.failure(.jsonParsingError(error)))
            return
        }

        uploadData(data, to: endpoint, with: request) { result in
            switch result {
            case .success(let data):
                do {
                    guard let response = try Response.parse(fromData: data) else {
                        completion(.failure(.dataParsingFailure(data)))
                        return
                    }
                    completion(.success(response))
                } catch {
                    completion(.failure(.jsonParsingError(error)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func post<Payload: JSONRepresentable & JSONParseable>(_ items: [Payload], to endpoint: APIEndpoint,
                                                                  completion: @escaping (PostResponse<Payload>) -> Void) {
        upload(items, to: endpoint, httpMethod: .post) { (result: NightscoutResult<[Payload]>) in
            let postResponse: PostResponse<Payload> = result.map { uploadedItems in
                let uploadedItems = Set(uploadedItems)
                let rejectedItems = Set(items).subtracting(uploadedItems)
                return (uploadedItems: uploadedItems, rejectedItems: rejectedItems)
            }
            completion(postResponse)
        }
    }

    private func put<Payload: JSONRepresentable & JSONParseable>(_ items: [Payload], to endpoint: APIEndpoint,
                                                                 completion: @escaping (OperationResult<Payload>) -> Void) {
        concurrentPerform(_put, items: items, endpoint: endpoint, completion: completion)
    }

    private func _put<Payload: JSONRepresentable & JSONParseable>(_ item: Payload, to endpoint: APIEndpoint,
                                                                  completion: @escaping (NightscoutError?) -> Void) {
        upload(item, to: endpoint, httpMethod: .put) { (result: NightscoutResult<AnyJSON>) in
            completion(result.error)
        }
    }

    private func delete<Payload: NightscoutIdentifiable>(_ items: [Payload], from endpoint: APIEndpoint,
                                                       completion: @escaping (OperationResult<Payload>) -> Void) {
        concurrentPerform(_delete, items: items, endpoint: endpoint, completion: completion)
    }

    private func _delete<Payload: NightscoutIdentifiable>(_ item: Payload, from endpoint: APIEndpoint,
                                                        completion: @escaping (NightscoutError?) -> Void) {
        guard credentials.apiSecret != nil else {
            completion(.missingAPISecret)
            return
        }

        guard var request = router.configureURLRequest(for: endpoint, httpMethod: .delete) else {
            completion(.invalidURL)
            return
        }

        request.url?.appendPathComponent(item.id.value)
        fetchData(from: endpoint, with: request) { result in
            completion(result.error)
        }
    }

    private typealias Operation<T> = (_ item: T, _ endpoint: APIEndpoint, _ completion: @escaping (NightscoutError?) -> Void) -> Void
    private func concurrentPerform<T>(_ operation: Operation<T>, items: [T], endpoint: APIEndpoint,
                                      completion: @escaping (OperationResult<T>) -> Void) {
        let rejections: ThreadSafe<Set<Rejection<T>>> = ThreadSafe([])
        let operationGroup = DispatchGroup()

        for item in items {
            operationGroup.enter()
            operation(item, endpoint) { error in
                if let error = error {
                    rejections.atomically { rejections in
                        let rejection = Rejection(item: item, error: error)
                        rejections.insert(rejection)
                    }
                }
                operationGroup.leave()
            }
        }

        let queue = queues.dispatchQueue(for: endpoint)
        operationGroup.notify(queue: queue) {
            let rejectionsSet = rejections.value
            let processedSet = Set(items).subtracting(rejectionsSet.map { $0.item })
            let operationResult: OperationResult = (processedItems: processedSet, rejections: rejectionsSet)
            completion(operationResult)
        }
    }
}