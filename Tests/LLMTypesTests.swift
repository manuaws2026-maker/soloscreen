import Testing
import Foundation
@testable import SoloScreen

@Suite("LLMTypes")
struct LLMTypesTests {

    // MARK: - LLMMessage

    @Test("text factory creates correct text-only message")
    func textFactory() {
        let msg = LLMMessage.text(role: .user, content: "Hello")
        #expect(msg.role == .user)
        #expect(msg.content.count == 1)

        if case .text(let text) = msg.content[0] {
            #expect(text == "Hello")
        } else {
            #expect(Bool(false), "Expected .text content part")
        }
    }

    @Test("text factory with system role")
    func textFactorySystem() {
        let msg = LLMMessage.text(role: .system, content: "You are helpful")
        #expect(msg.role == .system)
        #expect(msg.content.count == 1)

        if case .text(let text) = msg.content[0] {
            #expect(text == "You are helpful")
        } else {
            #expect(Bool(false), "Expected .text content part")
        }
    }

    @Test("text factory with assistant role")
    func textFactoryAssistant() {
        let msg = LLMMessage.text(role: .assistant, content: "Sure!")
        #expect(msg.role == .assistant)
    }

    @Test("text factory with empty string")
    func textFactoryEmpty() {
        let msg = LLMMessage.text(role: .user, content: "")
        if case .text(let text) = msg.content[0] {
            #expect(text == "")
        } else {
            #expect(Bool(false), "Expected .text content part")
        }
    }

    @Test("userWithImages creates message with image parts followed by text part")
    func userWithImages() {
        let imageData1 = Data([0x89, 0x50, 0x4E, 0x47])
        let imageData2 = Data([0xFF, 0xD8, 0xFF])

        let msg = LLMMessage.userWithImages(
            text: "What do you see?",
            images: [(imageData1, "image/png"), (imageData2, "image/jpeg")]
        )

        #expect(msg.role == .user)
        #expect(msg.content.count == 3) // 2 images + 1 text

        // First two parts are images
        if case .image(let data, let mime) = msg.content[0] {
            #expect(data == imageData1)
            #expect(mime == "image/png")
        } else {
            #expect(Bool(false), "Expected .image content part at index 0")
        }

        if case .image(let data, let mime) = msg.content[1] {
            #expect(data == imageData2)
            #expect(mime == "image/jpeg")
        } else {
            #expect(Bool(false), "Expected .image content part at index 1")
        }

        // Last part is text
        if case .text(let text) = msg.content[2] {
            #expect(text == "What do you see?")
        } else {
            #expect(Bool(false), "Expected .text content part at index 2")
        }
    }

    @Test("userWithImages with no images creates message with only text")
    func userWithImagesNoImages() {
        let msg = LLMMessage.userWithImages(text: "Just text", images: [])
        #expect(msg.role == .user)
        #expect(msg.content.count == 1)

        if case .text(let text) = msg.content[0] {
            #expect(text == "Just text")
        } else {
            #expect(Bool(false), "Expected .text content part")
        }
    }

    @Test("userWithImages with single image")
    func userWithImagesSingle() {
        let data = Data([0x00, 0x01])
        let msg = LLMMessage.userWithImages(text: "Describe", images: [(data, "image/webp")])
        #expect(msg.content.count == 2)
    }

    // MARK: - LLMMessage.Role

    @Test("Role raw values")
    func roleRawValues() {
        #expect(LLMMessage.Role.system.rawValue == "system")
        #expect(LLMMessage.Role.user.rawValue == "user")
        #expect(LLMMessage.Role.assistant.rawValue == "assistant")
    }

    // MARK: - LLMRequestOptions

    @Test("LLMRequestOptions default values")
    func requestOptionsDefaults() {
        let options = LLMRequestOptions()
        #expect(options.temperature == 0.7)
        #expect(options.maxTokens == nil)
        #expect(options.systemPrompt == nil)
    }

    @Test("LLMRequestOptions custom values")
    func requestOptionsCustom() {
        let options = LLMRequestOptions(
            temperature: 0.0,
            maxTokens: 4096,
            systemPrompt: "You are a coding assistant"
        )
        #expect(options.temperature == 0.0)
        #expect(options.maxTokens == 4096)
        #expect(options.systemPrompt == "You are a coding assistant")
    }

    @Test("LLMRequestOptions temperature boundary values")
    func requestOptionsTemperatureBoundaries() {
        let cold = LLMRequestOptions(temperature: 0.0)
        #expect(cold.temperature == 0.0)

        let hot = LLMRequestOptions(temperature: 2.0)
        #expect(hot.temperature == 2.0)
    }

    // MARK: - LLMError

    @Test("noAPIKey has correct error description")
    func noAPIKeyError() {
        let error = LLMError.noAPIKey
        #expect(error.errorDescription?.contains("API key") == true)
        #expect(error.errorDescription?.contains("Settings") == true)
    }

    @Test("invalidResponse includes status code in description")
    func invalidResponseError() {
        let error = LLMError.invalidResponse(statusCode: 401, body: "Unauthorized")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("401"))
        #expect(desc.contains("Unauthorized"))
    }

    @Test("invalidResponse truncates long body")
    func invalidResponseLongBody() {
        let longBody = String(repeating: "x", count: 500)
        let error = LLMError.invalidResponse(statusCode: 500, body: longBody)
        let desc = error.errorDescription ?? ""
        // Body should be truncated to prefix(200)
        #expect(desc.count < longBody.count + 50)
    }

    @Test("rateLimited with retry interval includes retry info")
    func rateLimitedWithRetry() {
        let error = LLMError.rateLimited(retryAfter: 30.0)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Rate limited"))
        #expect(desc.contains("30"))
    }

    @Test("rateLimited without retry interval has fallback message")
    func rateLimitedWithoutRetry() {
        let error = LLMError.rateLimited(retryAfter: nil)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Rate limited"))
        #expect(desc.contains("wait"))
    }

    @Test("networkError includes underlying error description")
    func networkError() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No connection"])
        let error = LLMError.networkError(underlying: underlying)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Network error"))
        #expect(desc.contains("No connection"))
    }

    @Test("decodingError includes underlying error description")
    func decodingError() {
        let underlying = NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing key"])
        let error = LLMError.decodingError(underlying: underlying)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("parse"))
        #expect(desc.contains("Missing key"))
    }

    @Test("modelNotSupported includes model name")
    func modelNotSupportedError() {
        let error = LLMError.modelNotSupported("llama-99b")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("llama-99b"))
        #expect(desc.contains("not supported"))
    }

    @Test("contextLengthExceeded has correct description")
    func contextLengthExceededError() {
        let error = LLMError.contextLengthExceeded
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("context window") || desc.contains("too long"))
    }

    @Test("cancelled has correct description")
    func cancelledError() {
        let error = LLMError.cancelled
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("cancelled"))
    }

    // MARK: - TokenUsage

    @Test("TokenUsage totalTokens is sum of prompt and completion")
    func tokenUsageTotal() {
        let usage = TokenUsage(promptTokens: 100, completionTokens: 50)
        #expect(usage.totalTokens == 150)
    }

    @Test("TokenUsage totalTokens with zero values")
    func tokenUsageTotalZero() {
        let usage = TokenUsage(promptTokens: 0, completionTokens: 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("TokenUsage totalTokens with large values")
    func tokenUsageTotalLarge() {
        let usage = TokenUsage(promptTokens: 128_000, completionTokens: 4_096)
        #expect(usage.totalTokens == 132_096)
    }

    // MARK: - LLMResponse

    @Test("LLMResponse creation")
    func responseCreation() {
        let usage = TokenUsage(promptTokens: 10, completionTokens: 20)
        let response = LLMResponse(
            content: "Hello!",
            model: "gpt-4o",
            finishReason: "stop",
            usage: usage
        )
        #expect(response.content == "Hello!")
        #expect(response.model == "gpt-4o")
        #expect(response.finishReason == "stop")
        #expect(response.usage?.totalTokens == 30)
    }

    @Test("LLMResponse with nil optional fields")
    func responseNilFields() {
        let response = LLMResponse(
            content: "Hi",
            model: "gpt-4o-mini",
            finishReason: nil,
            usage: nil
        )
        #expect(response.finishReason == nil)
        #expect(response.usage == nil)
    }

    // MARK: - LLMStreamDelta

    @Test("LLMStreamDelta with content")
    func streamDeltaWithContent() {
        let delta = LLMStreamDelta(content: "Hello", finishReason: nil)
        #expect(delta.content == "Hello")
        #expect(delta.finishReason == nil)
    }

    @Test("LLMStreamDelta with finish reason")
    func streamDeltaWithFinishReason() {
        let delta = LLMStreamDelta(content: nil, finishReason: "stop")
        #expect(delta.content == nil)
        #expect(delta.finishReason == "stop")
    }
}
