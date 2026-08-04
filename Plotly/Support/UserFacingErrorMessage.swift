import Foundation

enum UserFacingErrorMessage {
    static let loadRoute = "We could not load your saved route. Please close and reopen Plotly."
    static let loadBookmarks = "We could not load bookmarked routes right now."
    static let placeSearch = "We could not search places. Check your connection and try again."
    static let addStop = "We could not add that place. Please search for it again."
    static let saveRoute = "We could not save the route details. Please try again."
    static let openRoute = "We could not open that saved route."
    static let createRoute = "We could not create a new route. Please try again."
    static let saveNote = "We could not save the note. Please try again."
    static let removeStop = "We could not remove that stop. Please try again."
    static let reorderStops = "We could not reorder the stops. Please try again."
    static let planRoute = "We could not apply that route plan. Please try again."
    static let updateProgress = "We could not update the stop progress. Please try again."
    static let openDirections = "We could not open directions in Maps. Please try again."

    static let loadAccounts = "We could not load saved accounts. You can still continue as guest."
    static let signIn = "We could not sign you in. Please try again."
    static let appleSignInCanceled = "Apple sign-in was cancelled."
    static let appleSignInInvalidCredential = "We could not read your Apple account details. Please try again."
    static let accountUnavailable = "That account is no longer available. Please sign in again."
}
