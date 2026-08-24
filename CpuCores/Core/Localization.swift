import Foundation

func CCLocalized(_ key: String) -> String {
    NSLocalizedString(
        key,
        tableName: nil,
        bundle: .main,
        value: key,
        comment: ""
    )
}

func CCFormatted(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: CCLocalized(key),
        locale: Locale.current,
        arguments: arguments
    )
}
