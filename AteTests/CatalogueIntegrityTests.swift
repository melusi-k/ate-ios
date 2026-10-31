import XCTest
@testable import Ate

/// Integrity and matching tests for the curated food catalogue (#179).
/// Mirrors the offline manifest checks run against the USDA SR Legacy 2018-04 dataset.
final class CatalogueIntegrityTests: XCTestCase {

    /// Material qualifiers each record's aliases must preserve (from the source manifest).
    private let materialQualifiers: [String: [String]] = [
        "usda-srlegacy-172015": ["degermed", "unenriched", "white"],
        "usda-srlegacy-168929": ["degermed", "unenriched", "yellow"],
        "usda-srlegacy-169756": ["white", "long grain", "raw", "unenriched"],
        "usda-srlegacy-169761": ["all purpose", "unenriched"],
        "usda-srlegacy-170028": ["white", "flesh and skin", "raw"],
        "usda-srlegacy-169716": ["sorghum", "grain"],
        "usda-srlegacy-172420": ["raw"],
        "usda-srlegacy-175199": ["pinto", "raw"],
        "usda-srlegacy-175189": ["cranberry", "raw"],
        "usda-srlegacy-175182": ["baked", "canned", "plain"],
        "usda-srlegacy-174036": ["ground", "80", "20", "raw"],
        "usda-srlegacy-171052": ["meat only", "raw"],
        "usda-srlegacy-170599": ["beef", "tripe", "raw"],
        "usda-srlegacy-175140": ["pacific", "tomato sauce", "drained", "bone"],
        "usda-srlegacy-171287": ["whole", "raw", "fresh"],
        "usda-srlegacy-171265": ["whole", "3 25", "vitamin d"],
        "usda-srlegacy-173410": ["salted"],
        "usda-srlegacy-170000": ["raw"],
        "usda-srlegacy-169230": ["raw"],
        "usda-srlegacy-170457": ["red", "ripe", "raw"],
        "usda-srlegacy-170393": ["raw"],
        "usda-srlegacy-170427": ["sweet", "green", "raw"],
        "usda-srlegacy-169975": ["raw"],
        "usda-srlegacy-168462": ["raw"],
        "usda-srlegacy-169295": ["butternut", "raw"],
        "usda-srlegacy-171413": ["olive"],
        "usda-srlegacy-171017": ["sunflower", "linoleic", "less than 60"],
        "usda-srlegacy-169655": ["granulated"],
        "usda-srlegacy-173468": ["table"],
        "usda-srlegacy-175043": ["baker s", "active", "dry"]
    ]

    func testCatalogueRecordsVerifiedWithRightsAndFiniteValues() {
        XCTAssertFalse(NutritionFoodCatalogue.records.isEmpty)
        for record in NutritionFoodCatalogue.records {
            XCTAssertEqual(record.verificationStatus, .verified, record.id)
            XCTAssertTrue(record.usageRightsConfirmed, record.id)
            XCTAssertEqual(record.referenceQuantity, 100, record.id)
            XCTAssertEqual(record.sourceName, "USDA FoodData Central SR Legacy", record.id)
            XCTAssertEqual(record.sourceVersion, "2018-04", record.id)
            XCTAssertFalse(record.sourceRecordID.isEmpty, record.id)
            let values = [record.nutrients.energyKcal, record.nutrients.proteinGrams,
                          record.nutrients.carbohydratesGrams, record.nutrients.fatGrams,
                          record.nutrients.fibreGrams]
            for value in values {
                if let value { XCTAssertTrue(value.isFinite && value >= 0, record.id) }
            }
        }
    }

    private func normalizedName(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    func testCatalogueIDsAndNormalizedNamesAndAliasesUnique() {
        var ids = Set<String>()
        var labels = Set<String>()
        for record in NutritionFoodCatalogue.records {
            XCTAssertTrue(ids.insert(record.id).inserted, "duplicate id \(record.id)")
            for label in [record.name] + record.aliases {
                let normalized = normalizedName(label)
                XCTAssertTrue(labels.insert(normalized).inserted,
                              "normalized collision: \(label) on \(record.id)")
            }
        }
    }

    func testAliasesPreserveAllMaterialQualifiers() {
        for record in NutritionFoodCatalogue.records {
            guard let qualifiers = materialQualifiers[record.id] else {
                XCTFail("missing qualifier expectations for \(record.id)")
                continue
            }
            for alias in record.aliases {
                let normalized = normalizedName(alias)
                for qualifier in qualifiers {
                    let needle = normalizedName(qualifier)
                    if needle == "raw", normalized.contains("dry"),
                       ["usda-srlegacy-172420", "usda-srlegacy-175199", "usda-srlegacy-175189"].contains(record.id) {
                        continue // documented: for dry legumes, "dry" is the same as-sold uncooked state as source "raw"
                    }
                    XCTAssertTrue(normalized.contains(needle),
                                  "alias '\(alias)' on \(record.id) lost qualifier '\(qualifier)'")
                }
            }
        }
    }

    func testCalculatorMatchesStateQualifiedAlias() throws {
        let recipe = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "white rice, long-grain, raw, unenriched", quantity: 150, unit: "g", notes: nil)
        ])
        let result = RecipeNutritionCalculator(foods: NutritionFoodCatalogue.records).calculate(recipe)
        XCTAssertTrue(result.isComplete)
        let totalEnergyKcal = try XCTUnwrap(result.totalRecipe?.energyKcal)
        XCTAssertEqual(totalEnergyKcal, 547.5, accuracy: 0.01)
    }

    func testCalculatorSurfacesUnmappedSADishNameAsIncomplete() {
        let recipe = RecipeCard(servings: 2, ingredients: [
            Ingredient(name: "dry lentils", quantity: 100, unit: "g", notes: nil),
            Ingredient(name: "pap", quantity: 200, unit: "g", notes: nil)
        ])
        let result = RecipeNutritionCalculator(foods: NutritionFoodCatalogue.records).calculate(recipe)
        XCTAssertFalse(result.isComplete)
        XCTAssertNil(result.perServing)
        XCTAssertEqual(result.unmappedIngredients, ["pap"])
    }
}
