import CoreaderKit
import Foundation

// All command logic is in CoreaderKit (`CoreaderCommand`) so it can be tested; this file
// only connects it to the real library, the terminal and `/usr/bin/open`.
let command = CoreaderCommand(
    library: LibraryStore(root: LibraryConfig.load().libraryRoot),
    textStore: BookTextStore(),
    isTTY: isatty(STDOUT_FILENO) == 1,
    opener: openInBackground
)
let output = command.run(Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data(output.stdout.utf8))
FileHandle.standardError.write(Data(output.stderr.utf8))
exit(output.exitCode)
