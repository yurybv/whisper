import Foundation

struct RetryPolicy: Sendable, Equatable {
    let delays: [TimeInterval]

    init(delays: [TimeInterval] = [1, 2, 4]) {
        self.delays = delays
    }

    var maximumRetryCount: Int {
        delays.count
    }

    func shouldRetry(statusCode: Int) -> Bool {
        [429, 500, 502, 503, 504].contains(statusCode)
    }

    func shouldRetry(error: Error) -> Bool {
        guard !(error is CancellationError), let urlError = error as? URLError else {
            return false
        }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code)
    }

    func delay(forRetryAttempt attempt: Int, jitter: TimeInterval) -> TimeInterval? {
        guard delays.indices.contains(attempt) else {
            return nil
        }
        return delays[attempt] + max(0, jitter)
    }
}
