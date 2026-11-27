package app.relay.android.data

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LoansTest {
    private val spain = Locale.forLanguageTag("es-ES")
    private fun plain(text: String) = text.replace(' ', ' ').replace(' ', ' ')

    @Test fun ratesReadAsSpanishLendersQuoteThem() {
        assertEquals("1,50 %", plain(formatRate("1.5", spain)))
        assertEquals("3,839 %", plain(formatRate("3.839", spain)))
        assertEquals("—", formatRate(null, spain))
        assertEquals("—", formatRate("n/a", spain))
    }

    @Test fun termsAreWrittenInYearsAndMonths() {
        assertEquals("30 años", formatTerm(360))
        assertEquals("1 año y 1 mes", formatTerm(13))
        assertEquals("11 meses", formatTerm(11))
        assertNull(formatTerm(null))
    }

    @Test fun periodsDescribeTheirTermsAndReview() {
        val fixed = LoanRatePeriod(startsOn = "2025-12-12", rateKind = "fixed", baseRate = "2.7")
        val variable = LoanRatePeriod(startsOn = "2026-12-12", rateKind = "variable", referenceIndex = "euribor_12m", spread = "1.8",
            reviewIntervalMonths = 6, lenderName = "Bankinter")
        assertEquals("Fijo 2,70 % · revisión anual", plain(fixed.termsText()))
        assertEquals("Euríbor 12M + 1,80 % · revisión cada 6 meses · Bankinter", plain(variable.termsText()))
    }

    @Test fun aRevisionWithoutBonusesLeavesThemOut() {
        val revision = LoanRevision(effectiveOn = "2027-12-12", rate = "3.5", rateKind = "variable", referenceIndex = "other_index",
            referenceIndexName = "Other index", indexValue = "2.0", spread = "1.5", bonusPoints = "0.0")
        assertEquals("Other index 2,00 % + diferencial 1,50 %", plain(revision.compositionText()))
    }

    @Test fun subtypesHaveSpanishNames() {
        assertEquals("Hipoteca", loanSubtypeName("mortgage"))
        assertEquals("Préstamo", loanSubtypeName(null))
    }
}
