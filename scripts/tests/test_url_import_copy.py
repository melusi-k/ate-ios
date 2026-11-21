from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / 'Ate/Logic/JSONLD.swift').read_text()
TESTS = (ROOT / 'AteTests/JSONLDTests.swift').read_text()

class UrlImportCopyContracts(unittest.TestCase):
    def test_title_cleaning_is_applied_to_imported_titles_only(self):
        self.assertIn('static func cleanTitle(_ raw: String, host: String? = nil) -> String', SRC)
        self.assertIn('title: cleanTitle(decode(name), host: host)', SRC)
        # Ingredient and step text never pass through the title cleaner.
        self.assertNotIn('cleanTitle(s', SRC)
        self.assertEqual(SRC.count('cleanTitle('), SRC.count('cleanTitle(_ raw') + SRC.count('cleanTitle(decode(name)'), SRC)

    def test_marketing_blurb_filter_covers_the_observed_copy(self):
        self.assertIn('static func isMarketingBlurb(_ text: String) -> Bool', SRC)
        for phrase in ['"try the recipe"', '"explore our"']:
            self.assertIn(phrase, SRC)
        self.assertIn('description: blurb.flatMap { isMarketingBlurb($0) ? nil : $0 }', SRC)
        # The 300-character cap is preserved.
        self.assertIn('String($0.prefix(300))', SRC)

    def test_every_delimiter_requires_a_site_match(self):
        # r2: pipe, double colon, en/em dash and hyphen ALL strip only when the
        # suffix names the site; without a host nothing is stripped, and an
        # unstripped title is returned untrimmed (leading space survives).
        self.assertIn('let site = registrableName(host)', SRC)
        self.assertIn('for sep in [" | ", " :: ", " \\u{2013} ", " \\u{2014} ", " - "]', SRC)
        self.assertIn('if site.count >= 3, let i = t.range(of: sep, options: .backwards),', SRC)
        self.assertIn('return stripped ? t.trimmingCharacters(in: .whitespacesAndNewlines) : raw', SRC)
        self.assertNotIn('for sep in [" | ", " :: "]', SRC)

    def test_site_match_is_a_whole_name_boundary_not_substring(self):
        # r3: host eat.com must not strip "Chicken - Wheat and Cheese" (wheat only
        # CONTAINS eat). The suffix matches when its trimmed lowercase form equals
        # the registrable site name or holds it as its own token; the r2 substring
        # membership test is gone.
        self.assertIn('Self.suffixNamesSite(String(t[i.upperBound...]), site: site)', SRC)
        self.assertIn('static func suffixNamesSite(_ suffix: String, site: String) -> Bool', SRC)
        self.assertIn('return s == site || s.components(separatedBy: CharacterSet.alphanumerics.inverted).contains(site)', SRC)
        self.assertNotIn('].lowercased().contains(site)', SRC)

    def test_registrable_name_strips_www_and_public_suffixes(self):
        # r2: the first host label is never used ("www" matches nothing); a
        # leading www is dropped and co.za-style suffixes collapse.
        self.assertIn('static func registrableName(_ host: String) -> String', SRC)
        self.assertIn('if labels.first == "www" { labels.removeFirst() }', SRC)
        self.assertIn('return labels[labels.count - 3]', SRC)
        self.assertNotIn('host.lowercased().split(separator: ".").first', SRC)

    def test_host_flows_from_the_source_url(self):
        self.assertIn('let host = sourceURL.flatMap { URL(string: $0)?.host }', SRC)
        self.assertIn('card(from: node, host: host)', SRC)

    def test_swift_tests_assert_user_intent(self):
        for token in ['testSiteSuffixIsStrippedFromImportedTitle', 'testMarketingBlurbBecomesNoDescription',
                      'testIngredientTextKeepsBrandMarks', 'testHyphenSuffixOnlyWhenItNamesTheSite',
                      'testGenuineDescriptionsSurvive', 'XCTAssertNil(c.description',
                      # r2 pins, both sides:
                      'registrableName("www.lancewood.co.za"), "lancewood"',
                      'cleanTitle("Samp Recipe | FoodSite", host: "other.com"), "Samp Recipe | FoodSite"',
                      'cleanTitle("Samp Recipe | FoodSite"), "Samp Recipe | FoodSite"',
                      'cleanTitle(" | FoodSite", host: "foodsite.com"), " | FoodSite"',
                      'cleanTitle("Creamy Samp - Www", host: "www.lancewood.co.za"), "Creamy Samp - Www"',
                      # r3 collision fixture, both sides:
                      'testSiteNameMatchesOnlyOnAWholeNameBoundary',
                      'cleanTitle("Chicken - Wheat and Cheese", host: "eat.com"), "Chicken - Wheat and Cheese"',
                      'cleanTitle("Chicken - eat.com", host: "eat.com"), "Chicken"']:
            self.assertIn(token, TESTS)
        # The JSON-LD fixture is valid JSON: no Swift-style \u{...} escapes inside
        # the raw-string payload, and no out-of-scope `html` reference remains.
        payload = TESTS.split('let lancewoodHTML = #"""', 1)[1].split('"""#', 1)[0]
        self.assertNotIn('\\u{', payload)
        self.assertIn('LANCEWOOD\\u00AE', payload)
        # No out-of-scope `html` reference remains inside ImportedCopyTests (the
        # JSONLDTests class's own html property is in scope and stays).
        imported = TESTS.split('final class ImportedCopyTests', 1)[1]
        self.assertNotIn('fromHTML: html,', imported)

if __name__ == '__main__':
    unittest.main()
