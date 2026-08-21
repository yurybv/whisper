import Foundation

struct OpenAIConfiguration: Sendable, Equatable {
    let baseURL: URL
    let dictationModel: String
    let meetingModel: String
    let transformModel: String
    let maximumUploadBytes: Int

    init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        dictationModel: String = "gpt-transcribe",
        meetingModel: String = "gpt-4o-transcribe-diarize",
        transformModel: String = "gpt-5.6-luna",
        maximumUploadBytes: Int = 20 * 1024 * 1024
    ) {
        self.baseURL = baseURL
        self.dictationModel = dictationModel
        self.meetingModel = meetingModel
        self.transformModel = transformModel
        self.maximumUploadBytes = maximumUploadBytes
    }
}
