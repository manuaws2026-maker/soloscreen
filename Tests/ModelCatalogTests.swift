import Testing
import Foundation
@testable import SoloScreen

@Suite("ModelCatalog")
struct ModelCatalogTests {

    // MARK: - Catalog Contents

    @Test("all models is non-empty")
    func allNonEmpty() {
        #expect(!ModelCatalog.all.isEmpty)
    }

    @Test("all models equals openai + anthropic + google")
    func allComposition() {
        let expected = ModelCatalog.openai + ModelCatalog.anthropic + ModelCatalog.google
        #expect(ModelCatalog.all.count == expected.count)
        for (a, b) in zip(ModelCatalog.all, expected) {
            #expect(a.id == b.id)
        }
    }

    // MARK: - Model Validation

    @Test("Every model has a non-empty id")
    func nonEmptyIds() {
        for model in ModelCatalog.all {
            #expect(!model.id.isEmpty, "Model has empty id")
        }
    }

    @Test("Every model has a non-empty name")
    func nonEmptyNames() {
        for model in ModelCatalog.all {
            #expect(!model.name.isEmpty, "Model \(model.id) has empty name")
        }
    }

    @Test("Every model has a non-empty provider")
    func nonEmptyProviders() {
        for model in ModelCatalog.all {
            #expect(!model.provider.isEmpty, "Model \(model.id) has empty provider")
        }
    }

    @Test("Every model has a non-empty description")
    func nonEmptyDescriptions() {
        for model in ModelCatalog.all {
            #expect(!model.description.isEmpty, "Model \(model.id) has empty description")
        }
    }

    @Test("Every model has at least one strength")
    func nonEmptyStrengths() {
        for model in ModelCatalog.all {
            #expect(!model.strengths.isEmpty, "Model \(model.id) has no strengths")
        }
    }

    @Test("Every model has at least one weakness")
    func nonEmptyWeaknesses() {
        for model in ModelCatalog.all {
            #expect(!model.weaknesses.isEmpty, "Model \(model.id) has no weaknesses")
        }
    }

    @Test("Every model has contextWindow > 0")
    func positiveContextWindow() {
        for model in ModelCatalog.all {
            #expect(model.contextWindow > 0, "Model \(model.id) has contextWindow <= 0")
        }
    }

    // MARK: - Provider Filtering

    @Test("models(for: openai) returns only OpenAI models")
    func openaiFilter() {
        let models = ModelCatalog.models(for: "openai")
        #expect(!models.isEmpty)
        for model in models {
            #expect(model.provider == "openai", "Model \(model.id) is not OpenAI")
        }
        #expect(models.count == ModelCatalog.openai.count)
    }

    @Test("models(for: anthropic) returns only Anthropic models")
    func anthropicFilter() {
        let models = ModelCatalog.models(for: "anthropic")
        #expect(!models.isEmpty)
        for model in models {
            #expect(model.provider == "anthropic", "Model \(model.id) is not Anthropic")
        }
        #expect(models.count == ModelCatalog.anthropic.count)
    }

    @Test("models(for: google) returns only Google models")
    func googleFilter() {
        let models = ModelCatalog.models(for: "google")
        #expect(!models.isEmpty)
        for model in models {
            #expect(model.provider == "google", "Model \(model.id) is not Google")
        }
        #expect(models.count == ModelCatalog.google.count)
    }

    @Test("models(for: unknown) returns empty array")
    func unknownProviderFilter() {
        let models = ModelCatalog.models(for: "nonexistent_provider")
        #expect(models.isEmpty)
    }

    // MARK: - Model Lookup

    @Test("model(withId: gpt-4o) returns correct model")
    func lookupGPT4o() {
        let model = ModelCatalog.model(withId: "gpt-4o")
        #expect(model != nil)
        #expect(model?.name == "GPT-4o")
        #expect(model?.provider == "openai")
        #expect(model?.supportsVision == true)
    }

    @Test("model(withId: gpt-4o-mini) returns correct model")
    func lookupGPT4oMini() {
        let model = ModelCatalog.model(withId: "gpt-4o-mini")
        #expect(model != nil)
        #expect(model?.name == "GPT-4o Mini")
        #expect(model?.provider == "openai")
    }

    @Test("model(withId: claude-sonnet-4-6) returns correct model")
    func lookupClaudeSonnet() {
        let model = ModelCatalog.model(withId: "claude-sonnet-4-6")
        #expect(model != nil)
        #expect(model?.provider == "anthropic")
    }

    @Test("model(withId: nonexistent) returns nil")
    func lookupNonexistent() {
        let model = ModelCatalog.model(withId: "nonexistent-model-xyz")
        #expect(model == nil)
    }

    @Test("model(withId: empty string) returns nil")
    func lookupEmptyString() {
        let model = ModelCatalog.model(withId: "")
        #expect(model == nil)
    }

    // MARK: - Special Constants

    @Test("defaultModel exists in catalog")
    func defaultModelExists() {
        let model = ModelCatalog.model(withId: ModelCatalog.defaultModel)
        #expect(model != nil, "defaultModel '\(ModelCatalog.defaultModel)' not found in catalog")
    }

    @Test("defaultModel is gpt-4o-mini")
    func defaultModelValue() {
        #expect(ModelCatalog.defaultModel == "gpt-4o-mini")
    }

    @Test("freeTierModel exists in catalog")
    func freeTierModelExists() {
        let model = ModelCatalog.model(withId: ModelCatalog.freeTierModel)
        #expect(model != nil, "freeTierModel '\(ModelCatalog.freeTierModel)' not found in catalog")
    }

    @Test("freeTierModel is gpt-4o-mini")
    func freeTierModelValue() {
        #expect(ModelCatalog.freeTierModel == "gpt-4o-mini")
    }

    // MARK: - Uniqueness

    @Test("No duplicate model IDs in catalog")
    func noDuplicateIds() {
        let ids = ModelCatalog.all.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Found duplicate model IDs: \(ids.count) total vs \(uniqueIds.count) unique")
    }

    // MARK: - Vision Support

    @Test("Vision models have supportsVision true")
    func visionModels() {
        let visionModels = ModelCatalog.all.filter { $0.supportsVision }
        #expect(!visionModels.isEmpty, "Expected at least one vision model")
        for model in visionModels {
            #expect(model.supportsVision == true)
        }
    }

    // MARK: - CostTier

    @Test("CostTier display labels are correct")
    func costTierLabels() {
        #expect(ModelInfo.CostTier.free.displayLabel == "Free")
        #expect(ModelInfo.CostTier.low.displayLabel == "$")
        #expect(ModelInfo.CostTier.medium.displayLabel == "$$")
        #expect(ModelInfo.CostTier.high.displayLabel == "$$$")
        #expect(ModelInfo.CostTier.premium.displayLabel == "$$$$")
    }

    @Test("CostTier raw values are lowercase")
    func costTierRawValues() {
        #expect(ModelInfo.CostTier.free.rawValue == "free")
        #expect(ModelInfo.CostTier.low.rawValue == "low")
        #expect(ModelInfo.CostTier.medium.rawValue == "medium")
        #expect(ModelInfo.CostTier.high.rawValue == "high")
        #expect(ModelInfo.CostTier.premium.rawValue == "premium")
    }

    // MARK: - ModelInfo Equatable

    @Test("ModelInfo equality is based on id")
    func modelInfoEquality() {
        let a = ModelInfo(
            id: "test",
            name: "Test A",
            provider: "test",
            description: "Desc A",
            strengths: ["fast"],
            weaknesses: ["slow"],
            supportsVision: true,
            contextWindow: 1000,
            costTier: .low
        )
        let b = ModelInfo(
            id: "test",
            name: "Test B",
            provider: "other",
            description: "Desc B",
            strengths: ["smart"],
            weaknesses: ["expensive"],
            supportsVision: false,
            contextWindow: 2000,
            costTier: .high
        )
        #expect(a == b, "ModelInfo equality should be based on id only")
    }

    @Test("ModelInfo with different ids are not equal")
    func modelInfoInequality() {
        let a = ModelInfo(
            id: "model-a", name: "A", provider: "p", description: "d",
            strengths: ["s"], weaknesses: ["w"], supportsVision: false,
            contextWindow: 1000, costTier: .low
        )
        let b = ModelInfo(
            id: "model-b", name: "A", provider: "p", description: "d",
            strengths: ["s"], weaknesses: ["w"], supportsVision: false,
            contextWindow: 1000, costTier: .low
        )
        #expect(a != b)
    }
}
