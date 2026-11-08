package expo.modules.qaoverlay

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Bundle
import androidx.activity.compose.BackHandler
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.window.PopupProperties
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class QaOverlayActivity : ComponentActivity() {
  private var pendingCapture: File? = null
  private val gallery = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
    if (uri != null) {
      val video = contentResolver.getType(uri)?.startsWith("video/") == true
      importAttachment(video) { QaDraft.importFile(this, uri) }
    }
  }
  private val photo = registerForActivityResult(ActivityResultContracts.TakePicture()) { success -> finishCapture(success, false) }
  private val cameraVideo = registerForActivityResult(ActivityResultContracts.CaptureVideo()) { success -> finishCapture(success, true) }
  private val screen = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
    val data = result.data
    if (result.resultCode == Activity.RESULT_OK && data != null) {
      ContextCompat.startForegroundService(this, Intent(this, QaRecordingService::class.java).apply {
        putExtra("resultCode", result.resultCode)
        putExtra("data", data)
      })
      finish()
    }
  }

  @OptIn(ExperimentalMaterial3Api::class)
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    QaOverlayHost.hideButton()
    enableEdgeToEdge()
    QaLinearSession.open(this)
    pendingCapture = savedInstanceState?.getString("capture")?.let(::File)
    val metadata = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA).metaData
    val team = metadata?.getString("expo.modules.qaoverlay.TEAM") ?: "Product"
    setContent {
      QaOverlayTheme {
        var closeConfirmation by remember { mutableStateOf(false) }
        var preview by remember { mutableStateOf<QaAttachment?>(null) }
        var restoreField by remember { mutableStateOf<String?>(null) }
        val keyboard = LocalSoftwareKeyboardController.current
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScope()
        val dismiss: () -> Unit = { scope.launch { sheetState.hide(); finish() }; Unit }
        val requestClose: () -> Unit = {
          if (!QaLinearSession.busy && !QaDraft.importing) {
            if (QaDraft.hasContent) closeConfirmation = true else dismiss()
          }
        }
        val scroll = rememberScrollState()
        val attachmentsScroll = rememberScrollState()
        ModalBottomSheet(
          onDismissRequest = requestClose, sheetState = sheetState,
          sheetGesturesEnabled = false, dragHandle = null,
          properties = ModalBottomSheetProperties(shouldDismissOnBackPress = false, shouldDismissOnClickOutside = false),
          containerColor = MaterialTheme.colorScheme.background
        ) {
          BackHandler(enabled = preview == null) { requestClose() }
          BackHandler(enabled = preview != null) { preview = null }
          if (preview == null) {
            Composer(team, scroll, attachmentsScroll, requestClose,
              restoreField, { restoreField = null }) { attachment, field ->
              restoreField = field
              keyboard?.hide()
              preview = attachment
            }
          } else { Box(Modifier.fillMaxSize()) }
        }
        preview?.let { attachment ->
          QaAttachmentGallery(attachment, onClose = { preview = null })
        }
        if (closeConfirmation) {
          AlertDialog(onDismissRequest = { closeConfirmation = false }, title = { Text("Save this draft?") },
            confirmButton = {
              TextButton(onClick = { closeConfirmation = false; dismiss() }, enabled = !QaLinearSession.busy && !QaDraft.importing,
                modifier = Modifier.testTag("qa-overlay.save-draft")) { Text("Save draft") }
            },
            dismissButton = {
              TextButton(onClick = { closeConfirmation = false; QaLinearSession.discardDraft(); dismiss() },
                enabled = QaLinearSession.canDiscardDraft && !QaDraft.importing, modifier = Modifier.testTag("qa-overlay.discard")) {
                Text("Discard", color = MaterialTheme.colorScheme.error)
              }
            })
        }
      }
    }
  }

  override fun onSaveInstanceState(outState: Bundle) {
    outState.putString("capture", pendingCapture?.path)
    super.onSaveInstanceState(outState)
  }

  private fun importAttachment(video: Boolean, file: () -> File) {
    QaDraft.importing = true
    lifecycleScope.launch {
      var owned: File? = null
      try {
        val attachment = withContext(Dispatchers.IO) { file().also { owned = it }.let { QaDraft.attachment(it, video) } }
        QaDraft.attachments.add(attachment)
      } catch (error: Exception) {
        owned?.delete()
        QaDraft.error = error.message ?: "Could not import the attachment."
      } finally { QaDraft.importing = false }
    }
  }

  private fun finishCapture(success: Boolean, video: Boolean) {
    val file = pendingCapture ?: return
    pendingCapture = null
    if (success) importAttachment(video) { file } else file.delete()
  }

  private fun capture(video: Boolean) {
    try {
      val file = QaDraft.newFile(this, if (video) "mp4" else "jpg")
      pendingCapture = file
      if (video) cameraVideo.launch(QaDraft.uri(this, file)) else photo.launch(QaDraft.uri(this, file))
    } catch (error: Exception) {
      pendingCapture?.delete(); pendingCapture = null
      QaDraft.error = "Camera unavailable: ${error.message}"
    }
  }

  @OptIn(ExperimentalMaterial3Api::class)
  @Composable
  private fun Composer(team: String, scroll: ScrollState, attachmentsScroll: ScrollState, onDismiss: () -> Unit, restoreField: String?, onFocusRestored: () -> Unit, onPreview: (QaAttachment, String?) -> Unit) {
    val titleFocus = remember { FocusRequester() }
    val descriptionFocus = remember { FocusRequester() }
    var focusedField by remember { mutableStateOf<String?>(null) }
    val confirmation = remember { SnackbarHostState() }
    var initialFocusRequested by remember { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(QaLinearSession.authenticated, QaLinearSession.locked) {
      if (!QaLinearSession.authenticated) initialFocusRequested = false
      if (QaLinearSession.authenticated && !QaLinearSession.locked && !initialFocusRequested) {
        if (restoreField == "description") descriptionFocus.requestFocus() else titleFocus.requestFocus()
        keyboard?.show()
        initialFocusRequested = true
        onFocusRestored()
      }
    }
    Box(Modifier.fillMaxSize()) {
    Scaffold(
      modifier = Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }.imePadding(),
      contentWindowInsets = WindowInsets(0),
      snackbarHost = { SnackbarHost(confirmation, Modifier.testTag("qa-overlay.success")) },
      topBar = {
        CenterAlignedTopAppBar(
          windowInsets = WindowInsets(0),
          title = {
            if (QaLinearSession.authenticated) {
              var menu by remember { mutableStateOf(false) }
              Box {
                FilledTonalButton(onClick = { menu = true }, enabled = !QaLinearSession.locked,
                  shape = CircleShape, contentPadding = PaddingValues(horizontal = 12.dp),
                  colors = ButtonDefaults.filledTonalButtonColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface),
                  modifier = Modifier.widthIn(max = 240.dp).testTag("qa-overlay.team")) {
                  val selected = QaLinearSession.teams.firstOrNull { it.id == QaLinearSession.teamId }
                  LinearIcon(selected?.icon ?: "Team", selected?.color)
                  Spacer(Modifier.width(8.dp))
                  Text(selected?.name ?: team, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, properties = PopupProperties(focusable = false)) {
                  QaLinearSession.teams.forEach { choice -> DropdownMenuItem(text = { Text(choice.name) }, leadingIcon = { LinearIcon(choice.icon ?: "Team", choice.color) },
                    trailingIcon = { if (choice.id == QaLinearSession.teamId) Icon(Icons.Outlined.Check, "Selected") },
                    onClick = { menu = false; QaLinearSession.selectTeam(choice.id, this@QaOverlayActivity) }) }
                  HorizontalDivider()
                  DropdownMenuItem(text = { Text(QaLinearSession.viewer) }, onClick = {}, enabled = false)
                  DropdownMenuItem(text = { Text("Sign out on this device") }, onClick = { menu = false; QaLinearSession.signOut() })
                }
              }
            } else Text("QA reporter")
          },
          navigationIcon = {
            FilledTonalIconButton(onClick = onDismiss, enabled = !QaLinearSession.busy && !QaDraft.importing,
              modifier = Modifier.testTag("qa-overlay.close"),
              colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface)) {
              Icon(Icons.Outlined.Close, "Close reporter")
            }
          },
          actions = { FilledTonalIconButton(onClick = { QaLinearSession.submit() }, enabled = QaLinearSession.authenticated && !QaLinearSession.busy && !QaDraft.importing && (QaLinearSession.pending || (QaDraft.title.isNotBlank() && QaLinearSession.stateId.isNotEmpty())), modifier = Modifier.testTag("qa-overlay.submit")) { Icon(Icons.Outlined.ArrowUpward, if (QaLinearSession.pending) "Check submission" else "Submit ticket") } }
        )
      },
      bottomBar = {
        if (QaLinearSession.authenticated) Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
          if (QaLinearSession.pending && !QaLinearSession.busy) TextButton(onClick = { QaLinearSession.editPending() }) { Text("Edit report") }
          HorizontalFloatingToolbar(expanded = true, modifier = Modifier.fillMaxWidth()) {
            Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
              var statusMenu by remember { mutableStateOf(false) }
              Box {
                TextButton(onClick = { statusMenu = true }, enabled = !QaLinearSession.locked,
                  colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface), modifier = Modifier.testTag("qa-overlay.status")) {
                  val selected = QaLinearSession.states.firstOrNull { it.id == QaLinearSession.stateId }
                  LinearIcon(selected?.statusIcon ?: "IssueStatusTodo", selected?.color)
                  Spacer(Modifier.width(8.dp))
                  Text(selected?.name ?: "Choose status", maxLines = 1, softWrap = false)
                }
                DropdownMenu(expanded = statusMenu, onDismissRequest = { statusMenu = false }, properties = PopupProperties(focusable = false)) {
                  QaLinearSession.states.forEach { choice -> DropdownMenuItem(text = { Text(choice.name) }, leadingIcon = { LinearIcon(choice.statusIcon, choice.color) },
                    trailingIcon = { if (choice.id == QaLinearSession.stateId) Icon(Icons.Outlined.Check, "Selected") },
                    onClick = { statusMenu = false; QaLinearSession.stateId = choice.id }) }
                }
              }
              VerticalDivider(Modifier.height(24.dp).padding(horizontal = 8.dp))
            Tool(Icons.Outlined.PhotoLibrary, "Gallery") { gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }
            Tool(Icons.Outlined.PhotoCamera, "Take photo") { capture(false) }
            Tool(Icons.Outlined.Videocam, "Camera video") { capture(true) }
            Tool(Icons.Outlined.RadioButtonChecked, "Record screen") { screen.launch(getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent()) }

            }
          }
        }
      }
    ) { insets ->
      if (!QaLinearSession.authenticated) {
        Column(Modifier.fillMaxSize().padding(insets).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
          Text("Connect to Linear", style = MaterialTheme.typography.headlineSmall)
          Text(if (QaLinearSession.configured) "Sign in to create issues in your workspace." else "Configure the Linear Client ID and redirect URI in the Expo plugin to enable reporting.")
          if (QaLinearSession.configured) Button(onClick = { QaLinearSession.signIn(this@QaOverlayActivity) }, enabled = !QaLinearSession.busy) { Text("Sign in to Linear") }
          if (QaLinearSession.busy) { CircularProgressIndicator(); Text(QaLinearSession.progress) }
        }
      } else Column(Modifier.fillMaxSize().padding(insets).verticalScroll(scroll).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        BasicTextField(
          readOnly = QaLinearSession.locked,
          value = QaDraft.title, onValueChange = { QaDraft.title = it },
          textStyle = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface),
          modifier = Modifier.fillMaxWidth().focusRequester(titleFocus).onFocusChanged { if (it.isFocused) focusedField = "title" }.semantics { contentDescription = "Issue title" }.testTag("qa-overlay.title"),
          decorationBox = { field ->
            Box {
              if (QaDraft.title.isEmpty()) Text("Issue title", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
              field()
            }
          }
        )
        BasicTextField(
          readOnly = QaLinearSession.locked,
          value = QaDraft.description, onValueChange = { QaDraft.description = it },
          textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
          modifier = Modifier.fillMaxWidth().focusRequester(descriptionFocus).onFocusChanged { if (it.isFocused) focusedField = "description" }.semantics { contentDescription = "Description" }.testTag("qa-overlay.description"),
          minLines = 5,
          decorationBox = { field ->
            Box {
              if (QaDraft.description.isEmpty()) Text("Description…", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
              field()
            }
          }
        )
        if (QaDraft.importing) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (QaLinearSession.pending && !QaLinearSession.busy) Text("Submission needs confirmation. Use the submit button to check it before creating another report.")
        Row(Modifier.horizontalScroll(attachmentsScroll), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
          QaDraft.attachments.toList().forEach { attachment ->
            Box {
                Box(Modifier.size(208.dp, 156.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surface)
                  .clickable(onClickLabel = if (attachment.video) "Preview video" else "Preview image") { onPreview(attachment, focusedField) }
                  .semantics { contentDescription = if (attachment.video) "Preview video" else "Preview image" }, contentAlignment = Alignment.Center) {
                  attachment.thumbnail?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop, filterQuality = androidx.compose.ui.graphics.FilterQuality.High) }
                  if (attachment.video) Icon(Icons.Outlined.PlayCircle, null)
                }
              IconButton(onClick = { QaDraft.remove(attachment) }, enabled = !QaLinearSession.locked,
                modifier = Modifier.align(Alignment.TopEnd).offset(x = 8.dp, y = (-8).dp).size(44.dp)
                  .testTag("qa-overlay.attachment.remove.${attachment.file.name}")) {
                Box(Modifier.size(20.dp).background(Color.Gray.copy(alpha = 0.85f), CircleShape), contentAlignment = Alignment.Center) {
                  Icon(Icons.Outlined.Close, "Remove attachment", Modifier.size(12.dp), tint = Color.White)
                }
              }
            }
          }
        }
      }
    }
    if (QaLinearSession.busy) {
      Surface(Modifier.align(Alignment.Center), shape = MaterialTheme.shapes.large, tonalElevation = 6.dp) {
        Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
          CircularProgressIndicator()
          Text(QaLinearSession.progress, style = MaterialTheme.typography.bodyMedium)
        }
      }
    }
    }
    (QaLinearSession.error ?: QaDraft.error)?.let { message ->
      AlertDialog(onDismissRequest = { QaDraft.error = null; QaLinearSession.error = null }, title = { Text("Report unavailable") }, text = { Text(message) }, confirmButton = { TextButton(onClick = { QaDraft.error = null; QaLinearSession.error = null }) { Text("OK") } })
    }
    DisposableEffect(Unit) { onDispose { QaLinearSession.created = null } }
    LaunchedEffect(QaLinearSession.created?.id) {
      QaLinearSession.created?.let { issue ->
        confirmation.showSnackbar("Ticket ${issue.identifier} created", duration = SnackbarDuration.Short)
        if (QaLinearSession.created?.id == issue.id) QaLinearSession.created = null
      }
    }
  }

  @Composable
  private fun LinearIcon(name: String, hex: String?) {
    val color = remember(hex) {
      hex?.takeIf { it.matches(Regex("#[0-9a-fA-F]{6}")) }?.let { Color(android.graphics.Color.parseColor(it)) }
    } ?: MaterialTheme.colorScheme.onSurface
    Icon(painterResource(qaLinearIconResources[name] ?: R.drawable.qa_linear_team), null, Modifier.size(20.dp), tint = color)
  }

  @Composable
  private fun Tool(icon: ImageVector, label: String, action: () -> Unit) {
    IconButton(onClick = action, enabled = !QaDraft.importing && !QaLinearSession.locked, modifier = Modifier.size(48.dp).testTag("qa-overlay.tool.$label")) { Icon(icon, label, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurface) }
  }
}
