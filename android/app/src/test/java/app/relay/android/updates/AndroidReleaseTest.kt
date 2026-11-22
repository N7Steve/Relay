package app.relay.android.updates

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AndroidReleaseTest {
    private val json = Json { ignoreUnknownKeys = true }
    private val release = AndroidRelease(1234, "0.1.1234", APPLICATION_ID, 26, 1024, "a".repeat(64), "b".repeat(40))

    @Test fun parsesTheServerManifest() {
        val parsed = json.decodeFromString<UpdateResponse>("""{"enabled":true,"release":{"version_code":1234,"version_name":"0.1.1234",
            "application_id":"app.relay.android","min_sdk":26,"size":1024,"sha256":"${"a".repeat(64)}","commit":"${"b".repeat(40)}"}}""")
        assertEquals(release, parsed.release)
        parsed.release!!.validate()
    }

    @Test fun disabledChannelHasNoRelease() {
        assertEquals(UpdateResponse(false, null), json.decodeFromString<UpdateResponse>("""{"enabled":false,"release":null}"""))
    }

    @Test fun rejectsAnotherApplicationOrMalformedHash() {
        assertThrows(IllegalArgumentException::class.java) { release.copy(applicationId = "com.example").validate() }
        assertThrows(IllegalArgumentException::class.java) { release.copy(sha256 = "A".repeat(64)).validate() }
        assertThrows(IllegalArgumentException::class.java) { release.copy(size = 0).validate() }
    }
}
