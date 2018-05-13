//
//  NightscoutDataStore.swift
//  NightscoutKit
//
//  Created by Michael Pangburn on 3/23/18.
//  Copyright © 2018 Michael Pangburn. All rights reserved.
//

import Foundation


/// A highly configurable class that stores data produced or received
/// by the operations of an observed `Nightscout` instance.
open class NightscoutDataStore: _NightscoutObserver {
    /// Describes the set of possible options for a `NightscoutDataStore` instance.
    public struct Options: OptionSet {
        /// Cache received data.
        ///
        /// If this option is set, `NightscoutDataStore` properties will accumulate received data.
        /// If this option is not set, `NightscoutDataStore` properties will be replaced as
        /// the observed `Nightscout` instance performs operations.
        public static let cacheReceivedData = Options(rawValue: 1 << 0)

        /// When fetched data is received, only store data more recent than
        /// the most recently stored data.
        ///
        /// If the `cacheReceivedData` option is not set, this option has no effect.
        public static let ignoreOlderFetchedData = Options(rawValue: 1 << 1)

        /// Store the entries fetched by the observed `Nightscout` instance.
        public static let storeFetchedEntries = Options(rawValue: 1 << 2)

        /// Store the entries uploaded by the observed `Nightscout` instance.
        public static let storeUploadedEntries = Options(rawValue: 1 << 3)

        /// Store the entries that the observed `Nightscout` instance failed to upload.
        public static let storeFailedUploadEntries = Options(rawValue: 1 << 4)

        /// Store the treatments fetched by the observed `Nightscout` instance.
        public static let storeFetchedTreatments = Options(rawValue: 1 << 5)

        /// Store the treatments uploaded by the observed `Nightscout` instance.
        public static let storeUploadedTreatments = Options(rawValue: 1 << 6)

        /// Store the treatments that the observed `Nightscout` instance failed to upload.
        public static let storeFailedUploadTreatments = Options(rawValue: 1 << 7)

        /// Store the treatments updated by the observed `Nightscout` instance.
        public static let storeUpdatedTreatments = Options(rawValue: 1 << 8)

        /// Store the treatments that the observed `Nightscout` instance failed to update.
        public static let storeFailedUpdateTreatments = Options(rawValue: 1 << 9)

        /// Store the treatments deleted by the observed `Nightscout` instance.
        public static let storeDeletedTreatments = Options(rawValue: 1 << 10)

        /// Store the treatments that the observed `Nightscout` instance failed to delete.
        public static let storeFailedDeleteTreatments = Options(rawValue: 1 << 11)

        /// Store the profile records fetched by the observed `Nightscout` instance.
        public static let storeFetchedRecords = Options(rawValue: 1 << 12)

        /// Store the profile records uploaded by the observed `Nightscout` instance.
        public static let storeUploadedRecords = Options(rawValue: 1 << 13)

        /// Store the profile records that the observed `Nightscout` instance failed to upload.
        public static let storeFailedUploadRecords = Options(rawValue: 1 << 14)

        /// Store the profile records updated by the observed `Nightscout` instance.
        public static let storeUpdatedRecords = Options(rawValue: 1 << 15)

        /// Store the profile records that the observed `Nightscout` instance failed to update.
        public static let storeFailedUpdateRecords = Options(rawValue: 1 << 16)

        /// Store the profile records deleted by the observed `Nightscout` instance.
        public static let storeDeletedRecords = Options(rawValue: 1 << 17)

        /// Store the profile records that the observed `Nightscout` instance failed to delete.
        public static let storeFailedDeleteRecords = Options(rawValue: 1 << 18)

        /// Store the device statuses fetched by the observed `Nightscout` instance.
        public static let storeFetchedDeviceStatuses = Options(rawValue: 1 << 19)

        /// Store fetched entries, uploaded entries, and entries that failed to upload.
        public static let storeAllEntryData: Options = [.storeFetchedEntries, .storeUploadedEntries, .storeFailedUploadEntries]

        /// Store fetched treatments, uploaded treatments, treatments that failed to upload,
        /// updated treatments, treatments that failed to update, deleted treatments, and treatments that failed to delete.
        public static let storeAllTreatmentData: Options = [
            .storeFetchedTreatments, .storeUploadedTreatments, .storeFailedUploadTreatments, .storeUpdatedTreatments,
            .storeFailedUpdateTreatments, .storeDeletedTreatments, .storeFailedDeleteTreatments
        ]

        /// Store fetched records, uploaded records, records that failed to upload,
        /// updated records, records that failed to update, deleted records, and records that failed to delete.
        static let storeAllRecordData: Options = [
            .storeFetchedRecords, .storeUploadedRecords, .storeFailedUploadRecords, .storeUpdatedRecords,
            .storeFailedUpdateRecords, .storeDeletedRecords, .storeFailedDeleteRecords
        ]

        /// Store fetched device statuses.
        static let storeAllDeviceStatusData: Options = [.storeFetchedDeviceStatuses]

        /// Store fetched entries, treatments, records, and device statuses.
        public static let storeAllFetchedData: Options = [.storeFetchedEntries, .storeFetchedTreatments, .storeFetchedRecords, .storeFetchedDeviceStatuses]

        /// Store uploaded entries, treatments, and records.
        public static let storeAllUploadedData: Options = [.storeUploadedEntries, .storeUploadedTreatments, .storeUploadedRecords]

        /// Store entries, treatments, and records that failed to upload.
        public static let storeAllFailedUploadData: Options = [.storeFailedUploadEntries, .storeFailedUploadTreatments, .storeFailedUploadRecords]

        /// Store updated treatments and records.
        public static let storeAllUpdatedData: Options = [.storeUpdatedTreatments, .storeUpdatedRecords]

        /// Store treatments and records that failed to update.
        public static let storeAllFailedUpdateData: Options = [.storeFailedUpdateTreatments, .storeFailedUpdateRecords]

        /// Store deleted treatments and records.
        public static let storeAllDeletedData: Options = [.storeDeletedTreatments, .storeDeletedRecords]

        /// Store treatments and records that failed to delete.
        public static let storeAllFailedDeleteData: Options = [.storeFailedDeleteTreatments, .storeFailedDeleteRecords]

        /// Store all failed uploads, updates, and deletions.
        public static let storeAllFailureData: Options = [.storeAllFailedUploadData, .storeAllFailedUpdateData, .storeAllFailedDeleteData]

        /// Store the data produced by all operations.
        public static let storeAllData: Options = [.storeAllFetchedData, .storeAllUploadedData, .storeAllDeletedData, .storeAllFailureData]

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    // MARK: - Private properties

    private let _lastUpdated: ThreadSafe<Date?> = ThreadSafe(nil)

    private let _options: ThreadSafe<Options>

    private let _nightscoutHasAuthorization: ThreadSafe<Bool?> = ThreadSafe(nil)

    private let _fetchedStatus: ThreadSafe<NightscoutStatus?> = ThreadSafe(nil)

    private let _fetchedEntries: ThreadSafe<[NightscoutEntry]> = ThreadSafe([])
    private let _uploadedEntries: ThreadSafe<Set<NightscoutEntry>> = ThreadSafe([])
    private let _failedUploadEntries: ThreadSafe<Set<NightscoutEntry>> = ThreadSafe([])

    private let _fetchedTreatments: ThreadSafe<[NightscoutTreatment]> = ThreadSafe([])
    private let _uploadedTreatments: ThreadSafe<Set<NightscoutTreatment>> = ThreadSafe([])
    private let _failedUploadTreatments: ThreadSafe<Set<NightscoutTreatment>> = ThreadSafe([])
    private let _updatedTreatments: ThreadSafe<Set<NightscoutTreatment>> = ThreadSafe([])
    private let _failedUpdateTreatments: ThreadSafe<Set<NightscoutTreatment>> = ThreadSafe([])
    private let _deletedTreatments: ThreadSafe<Set<NightscoutTreatment>> = ThreadSafe([])
    private let _failedDeleteTreatments: ThreadSafe<Set<NightscoutTreatment>> = ThreadSafe([])

    private let _fetchedRecords: ThreadSafe<[NightscoutProfileRecord]> = ThreadSafe([])
    private let _uploadedRecords: ThreadSafe<Set<NightscoutProfileRecord>> = ThreadSafe([])
    private let _failedUploadRecords: ThreadSafe<Set<NightscoutProfileRecord>> = ThreadSafe([])
    private let _updatedRecords: ThreadSafe<Set<NightscoutProfileRecord>> = ThreadSafe([])
    private let _failedUpdateRecords: ThreadSafe<Set<NightscoutProfileRecord>> = ThreadSafe([])
    private let _deletedRecords: ThreadSafe<Set<NightscoutProfileRecord>> = ThreadSafe([])
    private let _failedDeleteRecords: ThreadSafe<Set<NightscoutProfileRecord>> = ThreadSafe([])

    private let _fetchedDeviceStatuses: ThreadSafe<[NightscoutDeviceStatus]> = ThreadSafe([])

    private let _lastError: ThreadSafe<NightscoutError?> = ThreadSafe(nil)

    // MARK: - Public properties

    /// The date at which the contents of the data store were last updated.
    public var lastUpdated: Date? { return _lastUpdated.value }

    /// The options to use in storing Nightscout data.
    ///
    /// This value is immutable. Specify options when creating the data store using `init(options:)`.
    public var options: Options { return _options.value }

    /// A boolean value representing whether the observed `Nightscout` instance has authorization.
    ///
    /// This value is set to `true` when `Nightscout.verifyAuthorization()` succeeds
    /// and `false` when the `Nightscout` instance produces an `.invalidURL`, `.missingAPISecret`, or `.unauthorized` error.
    public var nightscoutHasAuthorization: Bool? { return _nightscoutHasAuthorization.value }

    /// The most recently fetched site status.
    public var fetchedStatus: NightscoutStatus? { return _fetchedStatus.value }

    /// The most recently fetched entries.
    ///
    /// If `options` does not contain `.storeFetchedEntries`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate new entries as they are fetched,
    /// with the most recent entries at the front of the array.
    /// If not, this property be replaced each time the observed `Nightscout` instance fetches entries.
    public var fetchedEntries: [NightscoutEntry] { return _fetchedEntries.value }

    /// The most recently uploaded entries.
    ///
    /// If `options` does not contain `.storeUploadedEntries`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate entries as they are uploaded.
    /// If not, this property be replaced each time the observed `Nightscout` instance uploads entries.
    public var uploadedEntries: Set<NightscoutEntry> { return _uploadedEntries.value }

    /// The most entries that failed to upload.
    ///
    /// If `options` does not contain `.storeFailedUploadEntries`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate entries as they fail to upload.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to upload entries.
    public var failedUploadEntries: Set<NightscoutEntry> { return _failedUploadEntries.value }

    /// The most recently fetched treatments.
    ///
    /// If `options` does not contain `.storeFetchedTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate new treatments as they are fetched,
    /// with the most recent treatments at the front of the array.
    /// If not, this property be replaced each time the observed `Nightscout` instance fetches treatments.
    public var fetchedTreatments: [NightscoutTreatment] { return _fetchedTreatments.value }

    /// The most recently uploaded treatments.
    ///
    /// If `options` does not contain `.storeUploadedTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate treatments as they are uploaded.
    /// If not, this property be replaced each time the observed `Nightscout` instance uploads treatments.
    public var uploadedTreatments: Set<NightscoutTreatment> { return _uploadedTreatments.value }

    /// The most treatments that failed to upload.
    ///
    /// If `options` does not contain `.storeFailedUploadTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate treatments as they fail to upload.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to upload treatments.
    public var failedUploadTreatments: Set<NightscoutTreatment> { return _failedUploadTreatments.value }

    /// The most recently updated treatments.
    ///
    /// If `options` does not contain `.storeUpdatedTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate treatments as they are updated.
    /// If not, this property be replaced each time the observed `Nightscout` instance updates treatments.
    public var updatedTreatments: Set<NightscoutTreatment>{ return _updatedTreatments.value }

    /// The most treatments that failed to update.
    ///
    /// If `options` does not contain `.storeFailedUpdateTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate treatments as they fail to update.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to update treatments.
    public var failedUpdateTreatments: Set<NightscoutTreatment> { return _failedUpdateTreatments.value }

    /// The most recently deleted treatments.
    ///
    /// If `options` does not contain `.storeDeletedTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate treatments as they are deleted.
    /// If not, this property be replaced each time the observed `Nightscout` instance deletes treatments.
    public var deletedTreatments: Set<NightscoutTreatment> { return _deletedTreatments.value }

    /// The most treatments that failed to delete.
    ///
    /// If `options` does not contain `.storeFailedDeleteTreatments`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate treatments as they fail to delete.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to delete treatments.
    public var failedDeleteTreatments: Set<NightscoutTreatment> { return _failedDeleteTreatments.value }

    /// The most recently fetched profile records.
    ///
    /// If `options` does not contain `.storeFetchedRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate new records as they are fetched,
    /// with the most recent records at the front of the array.
    /// If not, this property be replaced each time the observed `Nightscout` instance fetches records.
    public var fetchedRecords: [NightscoutProfileRecord] { return _fetchedRecords.value }

    /// The most recently uploaded profile records.
    ///
    /// If `options` does not contain `.storeUploadedRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate records as they are uploaded.
    /// If not, this property be replaced each time the observed `Nightscout` instance uploads records.
    public var uploadedRecords: Set<NightscoutProfileRecord>  { return _uploadedRecords.value }

    /// The most profile records that failed to upload.
    ///
    /// If `options` does not contain `.storeFailedUploadRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate records as they fail to upload.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to upload records.
    public var failedUploadRecords: Set<NightscoutProfileRecord>  { return _failedUploadRecords.value }

    /// The most recently updated profile records.
    ///
    /// If `options` does not contain `.storeUpdatedRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate records as they are updated.
    /// If not, this property be replaced each time the observed `Nightscout` instance updates records.
    public var updatedRecords: Set<NightscoutProfileRecord>  { return _updatedRecords.value }

    /// The most profile records that failed to update.
    ///
    /// If `options` does not contain `.storeFailedUpdateRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate records as they fail to update.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to update records.
    public var failedUpdateRecords: Set<NightscoutProfileRecord>  { return _failedUpdateRecords.value }

    /// The most recently deleted profile records.
    ///
    /// If `options` does not contain `.storeDeletedRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate records as they are deleted.
    /// If not, this property be replaced each time the observed `Nightscout` instance deletes records.
    public var deletedRecords: Set<NightscoutProfileRecord> { return _deletedRecords.value }

    /// The most profile records that failed to delete.
    ///
    /// If `options` does not contain `.storeFailedDeleteRecords`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate records as they fail to delete.
    /// If not, this property be replaced each time the observed `Nightscout` instance fails to delete records.
    public var failedDeleteRecords: Set<NightscoutProfileRecord>  { return _failedDeleteRecords.value }

    /// The most recently fetched device statuses.
    ///
    /// If `options` does not contain `.storeFetchedDeviceStatuses`, this property will not be updated.
    ///
    /// If `options` contains `.cacheReceivedData`, this property will accumulate new device statuses as they are fetched,
    /// with the most recent device statuses at the front of the array.
    /// If not, this property be replaced each time the observed `Nightscout` instance fetches device statuses.
    public var fetchedDeviceStatuses: [NightscoutDeviceStatus] { return _fetchedDeviceStatuses.value }

    /// The `NightscoutError` most recently encountered by the observed `Nightscout` instance.
    public var lastError: NightscoutError? { return _lastError.value }

    // MARK: - Initializers

    /// Creates a new data store with the specified options.
    /// - Parameter options: The options for data storage.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Passing `true` is equivalent to including `.cacheReceivedData` in `options`.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public required init(options: Options, cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) {
        var options = options
        if cachingReceivedData {
            options.insert(.cacheReceivedData)
        }
        if ignoringOlderFetchedData {
            options.insert(.ignoreOlderFetchedData)
        }
        self._options = ThreadSafe(options)
    }

    /// Creates a new data store that stores only the fetched site status,
    /// verification status of authorization, and last error encountered.
    public convenience override init() {
        self.init(options: [])
    }

    /// Creates a new data store that stores the fetched site status,
    /// verification status of authorization, and last error encountered.
    public class func statusStore() -> Self {
        return self.init(options: [])
    }

    /// Creates a new data store that stores all entry data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func entryStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllEntryData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all treatment data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func treatmentStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllTreatmentData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all profile record data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func recordStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllRecordData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all device status data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func deviceStatusStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllDeviceStatusData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all fetched data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func fetchStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllFetchedData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all uploaded data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func uploadStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllUploadedData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all data that failed to upload.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func failedUploadStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllFailedUploadData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all updated data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func updateStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllUpdatedData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all data that failed to update.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func failedUpdateStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllFailedUpdateData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all deleted data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func deleteStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllDeletedData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all data that failed to delete.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func failedDeleteStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllFailedDeleteData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores data produced by failed operations.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func failureStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllFailureData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    /// Creates a new data store that stores all data.
    /// - Parameter cachingReceivedData: A boolean value determining whether the data store should cache received data.
    ///                                  If this value is `false`, previously received data will be replaced by new incoming data.
    ///                                  Defaults to `true`.
    /// - Parameter ignoringOlderFetchedData: A boolean value determining whether any data received that is older than
    ///                                       the most recently received data should be ignored (i.e. not cached).
    ///                                       If `cachingReceivedData` is `false`, this option has no effect.
    ///                                       Passing `true` is equivalent to including `.ignoreOlderFetchedData` in `options`.
    ///                                       Defaults to `true`.
    public class func allDataStore(cachingReceivedData: Bool = true, ignoringOlderFetchedData: Bool = true) -> Self {
        return self.init(options: .storeAllData, cachingReceivedData: cachingReceivedData, ignoringOlderFetchedData: ignoringOlderFetchedData)
    }

    // MARK: - Cache clearing

    /// Clears the cached verification status of authorization.
    public func clearAuthorizationCache() {
        _nightscoutHasAuthorization.atomicallyAssign(to: nil)
    }

    /// Clears the cached fetched site status.
    public func clearFetchedStatusCache() {
        _fetchedStatus.atomicallyAssign(to: nil)
    }

    /// Clears the cached fetched entries.
    public func clearFetchedEntriesCache() {
        clearCache(\._fetchedEntries)
    }

    /// Clears the cached uploaded entries.
    public func clearUploadedEntriesCache() {
        clearCache(\._uploadedEntries)
    }

    /// Clears the cached entries that failed to upload.
    public func clearFailedUploadEntriesCache() {
        clearCache(\._failedUploadEntries)
    }

    /// Clears the cached fetched treaments.
    public func clearFetchedTreatmentsCache() {
        clearCache(\._fetchedTreatments)
    }

    /// Clears the cached uploaded treaments.
    public func clearUploadedTreatmentsCache() {
        clearCache(\._uploadedTreatments)
    }

    /// Clears the cached treaments that failed to upload.
    public func clearFailedUploadTreatmentsCache() {
        clearCache(\._failedUploadTreatments)
    }

    /// Clears the cached updated treaments.
    public func clearUpdatedTreatmentsCache() {
        clearCache(\._updatedTreatments)
    }

    /// Clears the cached treaments that failed to update.
    public func clearFailedUpdateTreatmentsCache() {
        clearCache(\._failedUpdateTreatments)
    }

    /// Clears the cached deleted treaments.
    public func clearDeletedTreatmentsCache() {
        clearCache(\._deletedTreatments)
    }

    /// Clears the cached treaments that failed to delete.
    public func clearFailedDeleteTreatmentsCache() {
        clearCache(\._failedDeleteTreatments)
    }

    /// Clears the cached fetched profile records.
    public func clearFetchedRecordsCache() {
        clearCache(\._fetchedRecords)
    }

    /// Clears the cached uploaded profile records.
    public func clearUploadedRecordsCache() {
        clearCache(\._uploadedRecords)
    }

    /// Clears the cached profile records that failed to upload.
    public func clearFailedUploadRecordsCache() {
        clearCache(\._failedUploadRecords)
    }

    /// Clears the cached updated profile records.
    public func clearUpdatedRecordsCache() {
        clearCache(\._updatedRecords)
    }

    /// Clears the cached profile records that failed to update.
    public func clearFailedUpdateRecordsCache() {
        clearCache(\._failedUpdateRecords)
    }

    /// Clears the cached deleted profile records.
    public func clearDeletedRecordsCache() {
        clearCache(\._deletedRecords)
    }

    /// Clears the cached profile records that failed to delete.
    public func clearFailedDeleteRecordsCache() {
        clearCache(\._failedDeleteRecords)
    }

    /// Clears the cached fetched device statuses.
    public func clearFetchedDeviceStatusesCache() {
        clearCache(\._fetchedDeviceStatuses)
    }

    /// Clears the cached error.
    public func clearErrorCache() {
        _lastError.atomicallyAssign(to: nil)
    }

    /// Clears all cached entry data.
    public func clearEntryDataCache() {
        clearFetchedEntriesCache()
        clearUploadedEntriesCache()
        clearFailedUploadEntriesCache()
    }

    /// Clears all cached treatment data.
    public func clearTreatmentDataCache() {
        clearFetchedTreatmentsCache()
        clearUploadedTreatmentsCache()
        clearFailedUploadTreatmentsCache()
        clearUpdatedTreatmentsCache()
        clearFailedUpdateTreatmentsCache()
        clearDeletedTreatmentsCache()
        clearFailedDeleteTreatmentsCache()
    }

    /// Clears all cached profile record data.
    public func clearRecordDataCache() {
        clearFetchedRecordsCache()
        clearUploadedRecordsCache()
        clearFailedUploadRecordsCache()
        clearUpdatedRecordsCache()
        clearFailedUpdateRecordsCache()
        clearDeletedRecordsCache()
        clearFailedDeleteRecordsCache()
    }

    /// Clears all cached device status data.
    public func clearDeviceStatusCache() {
        clearFetchedDeviceStatusesCache()
    }

    /// Clears all cached fetched data.
    public func clearFetchedDataCache() {
        clearFetchedDeviceStatusesCache()
        clearFetchedEntriesCache()
        clearFetchedTreatmentsCache()
        clearFetchedRecordsCache()
        clearFetchedDeviceStatusesCache()
    }

    /// Clears all cached uploaded data.
    public func clearUploadedDataCache() {
        clearUploadedEntriesCache()
        clearUploadedTreatmentsCache()
        clearUploadedRecordsCache()
    }

    /// Clears all cached data that failed to upload.
    public func clearFailedUploadDataCache() {
        clearFailedUploadEntriesCache()
        clearFailedUploadTreatmentsCache()
        clearFailedUploadRecordsCache()
    }

    /// Clears all cached updated data.
    public func clearUpdatedDataCache() {
        clearUpdatedTreatmentsCache()
        clearFailedUpdateRecordsCache()
    }

    /// Clears all cached data that failed to update.
    public func clearFailedUpdateDataCache() {
        clearFailedUpdateTreatmentsCache()
        clearFailedUpdateRecordsCache()
    }

    /// Clears all cached deleted data.
    public func clearDeletedDataCache() {
        clearDeletedTreatmentsCache()
        clearDeletedRecordsCache()
    }

    /// Clears all cached data that failed to delete.
    public func clearFailedDeleteDataCache() {
        clearFailedDeleteTreatmentsCache()
        clearFailedDeleteRecordsCache()
    }

    /// Clears all data that failed to upload, update, or delete, along with the cached error.
    public func clearFailureDataCache() {
        clearFailedUploadDataCache()
        clearFailedUpdateDataCache()
        clearFailedDeleteDataCache()
        clearErrorCache()
    }

    /// Clears all cached data.
    public func clearAllDataCache() {
        clearFetchedDataCache()
        clearUploadedDataCache()
        clearUpdatedDataCache()
        clearFailureDataCache()
    }

    private func clearCache<C: ElementRemovableCollection>(_ keyPath: KeyPath<NightscoutDataStore, ThreadSafe<C>>) {
        self[keyPath: keyPath].atomically { (values: inout C) in
            values.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - NightscoutObserver

    open override func nightscoutDidVerifyAuthorization(_ nightscout: Nightscout) {
        _nightscoutHasAuthorization.atomicallyAssign(to: true)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFetchStatus status: NightscoutStatus) {
        _fetchedStatus.atomicallyAssign(to: status)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFetchEntries entries: [NightscoutEntry]) {
        guard options.contains(.storeFetchedEntries) else { return }
        prependOrReplace(entries, keyPath: \._fetchedEntries)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didUploadEntries entries: Set<NightscoutEntry>) {
        guard options.contains(.storeUploadedEntries) else { return }
        formUnionOrReplace(entries, keyPath: \._uploadedEntries)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToUploadEntries entries: Set<NightscoutEntry>) {
        guard options.contains(.storeFailedUploadEntries) else { return }
        formUnionOrReplace(entries, keyPath: \._failedUploadEntries)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFetchTreatments treatments: [NightscoutTreatment]) {
        guard options.contains(.storeFetchedTreatments) else { return }
        prependOrReplace(treatments, keyPath: \._fetchedTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didUploadTreatments treatments: Set<NightscoutTreatment>) {
        guard options.contains(.storeUploadedTreatments) else { return }
        formUnionOrReplace(treatments, keyPath: \._uploadedTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToUploadTreatments treatments: Set<NightscoutTreatment>) {
        guard options.contains(.storeFailedUploadTreatments) else { return }
        formUnionOrReplace(treatments, keyPath: \._failedUploadTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didUpdateTreatments treatments: Set<NightscoutTreatment>) {
        guard options.contains(.storeUpdatedTreatments) else { return }
        formUnionOrReplace(treatments, keyPath: \._updatedTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToUpdateTreatments treatments: Set<NightscoutTreatment>) {
        guard options.contains(.storeFailedUpdateTreatments) else { return }
        formUnionOrReplace(treatments, keyPath: \._failedUpdateTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didDeleteTreatments treatments: Set<NightscoutTreatment>) {
        guard options.contains(.storeDeletedTreatments) else { return }
        formUnionOrReplace(treatments, keyPath: \._deletedTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToDeleteTreatments treatments: Set<NightscoutTreatment>) {
        guard options.contains(.storeFailedDeleteTreatments) else { return }
        formUnionOrReplace(treatments, keyPath: \._failedDeleteTreatments)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFetchProfileRecords records: [NightscoutProfileRecord]) {
        guard options.contains(.storeFetchedRecords) else { return }
        prependOrReplace(records, keyPath: \._fetchedRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didUploadProfileRecords records: Set<NightscoutProfileRecord>) {
        guard options.contains(.storeUploadedRecords) else { return }
        formUnionOrReplace(records, keyPath: \._uploadedRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToUploadProfileRecords records: Set<NightscoutProfileRecord>) {
        guard options.contains(.storeFailedUploadRecords) else { return }
        formUnionOrReplace(records, keyPath: \._failedUploadRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didUpdateProfileRecords records: Set<NightscoutProfileRecord>) {
        guard options.contains(.storeUpdatedRecords) else { return }
        formUnionOrReplace(records, keyPath: \._updatedRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToUpdateProfileRecords records: Set<NightscoutProfileRecord>) {
        guard options.contains(.storeFailedUpdateRecords) else { return }
        formUnionOrReplace(records, keyPath: \._failedUpdateRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didDeleteProfileRecords records: Set<NightscoutProfileRecord>) {
        guard options.contains(.storeDeletedRecords) else { return }
        formUnionOrReplace(records, keyPath: \._deletedRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFailToDeleteProfileRecords records: Set<NightscoutProfileRecord>) {
        guard options.contains(.storeFailedDeleteRecords) else { return }
        formUnionOrReplace(records, keyPath: \._failedDeleteRecords)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didFetchDeviceStatuses deviceStatuses: [NightscoutDeviceStatus]) {
        guard options.contains(.storeFetchedDeviceStatuses) else { return }
        prependOrReplace(deviceStatuses, keyPath: \._fetchedDeviceStatuses)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    open override func nightscout(_ nightscout: Nightscout, didErrorWith error: NightscoutError) {
        switch error {
        case .invalidURL, .missingAPISecret, .unauthorized:
            _nightscoutHasAuthorization.atomicallyAssign(to: false)
        default:
            break
        }
        _lastError.atomicallyAssign(to: error)
        _lastUpdated.atomicallyAssign(to: Date())
    }

    private func prependOrReplace<T: TimelineValue>(_ newValues: [T], keyPath: KeyPath<NightscoutDataStore, ThreadSafe<[T]>>) {
        if options.contains(.cacheReceivedData) {
            self[keyPath: keyPath].atomically { (storedValues: inout [T]) in
                if options.contains(.ignoreOlderFetchedData),
                    let mostRecentStoredValue = storedValues.first,
                    let overlappingValue = newValues.index(where: { $0.date <= mostRecentStoredValue.date }) {
                        let moreRecentValues = newValues[..<overlappingValue]
                        storedValues.insert(contentsOf: moreRecentValues, at: 0)
                } else {
                    storedValues.insert(contentsOf: newValues, at: 0)
                }
            }
        } else {
            self[keyPath: keyPath].atomicallyAssign(to: newValues)
        }
    }

    private func formUnionOrReplace<T>(_ newValues: Set<T>, keyPath: KeyPath<NightscoutDataStore, ThreadSafe<Set<T>>>) {
        if options.contains(.cacheReceivedData) {
            self[keyPath: keyPath].atomically { (storedValues: inout Set<T>) in
                storedValues.formUnion(newValues)
            }
        } else {
            self[keyPath: keyPath].atomicallyAssign(to: newValues)
        }
    }
}

private protocol ElementRemovableCollection: Collection {
    mutating func removeAll(keepingCapacity: Bool)
}

extension Array: ElementRemovableCollection { }
extension Set: ElementRemovableCollection { }