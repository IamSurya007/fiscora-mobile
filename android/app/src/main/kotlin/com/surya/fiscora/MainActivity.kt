package com.surya.fiscora

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.surya.fiscora/sms_channel"
    private var pendingIntentTransaction: HashMap<String, Any>? = null

    companion object {
        private const val INTENT_TXN_ID = "notification-intent"
        private var instance: MainActivity? = null

        fun onLiveTransactionCaptured(txnMap: HashMap<String, Any>) {
            instance?.let { activity ->
                activity.runOnUiThread {
                    activity.flutterEngine?.let { engine ->
                        MethodChannel(engine.dartExecutor.binaryMessenger, "com.surya.fiscora/sms_channel")
                            .invokeMethod("onTransactionCaptured", txnMap)
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        handleIntent(intent)
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        sendPendingTransactionToFlutter()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent != null && intent.hasExtra("amount")) {
            val amount = intent.getDoubleExtra("amount", 0.0)
            val merchant = intent.getStringExtra("merchant") ?: "Unknown"
            val isDebit = intent.getBooleanExtra("isDebit", true)
            val date = intent.getStringExtra("date") ?: ""
            val body = intent.getStringExtra("body") ?: ""
            val source = intent.getStringExtra("source") ?: "sms"
            val sender = intent.getStringExtra("sender") ?: ""
            val sentAtMs = intent.getLongExtra("sentAtMs", 0L)
            val receivedAtMs = intent.getLongExtra("receivedAtMs", 0L)

            pendingIntentTransaction = hashMapOf<String, Any>(
                "amount" to amount,
                "merchant" to merchant,
                "isDebit" to isDebit,
                "date" to date,
                "body" to body,
                "source" to source,
                "sender" to sender,
                "id" to INTENT_TXN_ID
            ).apply {
                if (sentAtMs > 0) put("sentAtMs", sentAtMs)
                if (receivedAtMs > 0) put("receivedAtMs", receivedAtMs)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingTransactions" -> {
                    val list = getPendingTransactionsList()
                    result.success(list)
                }
                "getPendingTransaction" -> {
                    val list = getPendingTransactionsList()
                    if (list.isNotEmpty()) {
                        result.success(list.first())
                    } else {
                        result.success(null)
                    }
                }
                "removePendingTransactions" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    removePendingTransactions(ids)
                    result.success(true)
                }
                // Kept for older Dart builds; removes only what is currently queued.
                "clearPendingTransactions" -> {
                    removePendingTransactions(getPendingTransactionsList().mapNotNull { it["id"] as? String })
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getPendingTransactionsList(): List<HashMap<String, Any>> {
        val resultList = ArrayList(PendingSmsStore.list(this))

        // A notification tap carries the transaction too; it is normally already queued.
        pendingIntentTransaction?.let { intentTxn ->
            val exists = resultList.any {
                it["body"] == intentTxn["body"] && it["sender"] == intentTxn["sender"]
            }
            if (!exists) resultList.add(intentTxn)
        }
        return resultList
    }

    private fun removePendingTransactions(ids: Collection<String>) {
        PendingSmsStore.remove(this, ids)
        if (INTENT_TXN_ID in ids) pendingIntentTransaction = null
        // The intent copy is a duplicate once its queued twin has been handled.
        pendingIntentTransaction?.let { intentTxn ->
            if (PendingSmsStore.list(this).none { it["body"] == intentTxn["body"] }) {
                pendingIntentTransaction = null
            }
        }
    }

    // Items stay queued until Dart acknowledges them via removePendingTransactions.
    private fun sendPendingTransactionToFlutter() {
        flutterEngine?.let { engine ->
            for (txn in getPendingTransactionsList()) {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onTransactionCaptured", txn)
            }
        }
    }
}
