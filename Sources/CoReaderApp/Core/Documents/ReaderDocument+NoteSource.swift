extension ReaderDocument {
    /// Notes and highlights are keyed by the full path, so two files that share a
    /// name in different folders keep separate note lists.
    var noteSourceIdentifier: String {
        fileURL.standardizedFileURL.path
    }

    /// Notes saved before scoping moved to the full path carry only the filename.
    var legacyNoteSourceIdentifier: String {
        fileURL.lastPathComponent
    }
}
