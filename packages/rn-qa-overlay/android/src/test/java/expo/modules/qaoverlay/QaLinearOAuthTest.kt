package expo.modules.qaoverlay

import org.junit.Assert.*
import org.junit.Test

class QaLinearOAuthTest {
  private val redirect = "dev.example.qa://linear/callback"
  @Test fun validatesCallbackAndDecodedCode() {
    assertEquals("a+b", QaLinearOAuth.callback("$redirect?code=a%2Bb&state=s", redirect, "s"))
    for (address in listOf(
      "$redirect?code=a&state=wrong", "$redirect?code=a&code=b&state=s",
      "$redirect?code=a&state=s&state=s", "$redirect?code=a&state=s#fragment",
      "$redirect?code=a&state=s&error=denied", "$redirect?code=&state=s",
      "dev.example.qa://evil/callback?code=a&state=s",
      "dev.example.qa://user@linear/callback?code=a&state=s",
      "https://linear/callback?code=a&state=s", "invalid:%"
    )) assertNull(address, QaLinearOAuth.callback(address, redirect, "s"))
  }
  @Test fun formEncodesReservedCharacters() {
    assertEquals("code=a%2Bb%26c%3Dd&redirect_uri=dev.example.qa%3A%2F%2Flinear%2Fcallback", QaLinearOAuth.form(linkedMapOf("code" to "a+b&c=d", "redirect_uri" to redirect)))
  }
  @Test fun workflowIconsHaveBundledResources() {
    val expected = mapOf("triage" to "IssueStatusTriage", "backlog" to "IssueStatusBacklog",
      "unstarted" to "IssueStatusTodo", "started" to "IssueStatusStarted", "completed" to "IssueStatusDone",
      "canceled" to "StatusCanceled", "duplicate" to "StatusDuplicate", "unknown" to "IssueStatusTodo")
    for ((type, icon) in expected) {
      assertEquals(icon, QaLinearChoice("state", "Status", type).statusIcon)
      assertNotNull(qaLinearIconResources[icon])
    }
    assertEquals(317, qaLinearIconResources.size)
    assertNotNull(qaLinearIconResources["Team"])
    assertNull(qaLinearIconResources["FutureUnknownIcon"])
  }
  @Test fun emptyDraftIgnoresWhitespaceAndIncludesAttachments() {
    val owned = java.io.File.createTempFile("qa-draft", ".png")
    try {
      QaDraft.title = " \n"; QaDraft.description = "\t"
      assertFalse(QaDraft.hasContent)
      QaDraft.title = "Bug"
      assertTrue(QaDraft.hasContent)
      QaDraft.title = ""; QaDraft.description = "Details"
      assertTrue(QaDraft.hasContent)
      QaDraft.description = ""
      QaDraft.attachments.add(QaAttachment(owned, false, null))
      assertTrue(QaDraft.hasContent)
    } finally { QaDraft.discard(); owned.delete() }
  }

  @Test fun discardPreservesUnconfirmedSubmissionsAndDeletesOnlyOwnedAttachments() {
    val owned = java.io.File.createTempFile("qa-owned", ".png")
    val unrelated = java.io.File.createTempFile("qa-unrelated", ".png")
    val receipt = QaLinearSession::class.java.getDeclaredField("submissionId").apply { isAccessible = true }
    try {
      QaDraft.title = "Keep this report"
      QaDraft.attachments.add(QaAttachment(owned, false, null))
      receipt.set(null, "unconfirmed-issue")
      QaLinearSession.discardDraft()
      assertEquals("Keep this report", QaDraft.title)
      assertTrue(owned.exists())
      assertEquals(1, QaDraft.attachments.size)
      receipt.set(null, null)
      QaLinearSession.discardDraft()
      assertEquals("", QaDraft.title)
      assertTrue(QaDraft.attachments.isEmpty())
      assertFalse(owned.exists())
      assertTrue(unrelated.exists())
    } finally {
      receipt.set(null, null)
      QaDraft.discard()
      owned.delete(); unrelated.delete()
    }
  }

}
