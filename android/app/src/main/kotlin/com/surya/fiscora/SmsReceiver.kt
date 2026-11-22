package com.surya.fiscora

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.regex.Pattern

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "android.provider.Telephony.SMS_RECEIVED") {
            val bundle = intent.extras
            if (bundle != null) {
                try {
                    val pdus = bundle.get("pdus") as Array<*>?
                    if (pdus != null) {
                        val format = bundle.getString("format")
                        val messages = pdus.map { pdu ->
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                SmsMessage.createFromPdu(pdu as ByteArray, format)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsMessage.createFromPdu(pdu as ByteArray)
                            }
                        }

                        // A long SMS arrives as several PDUs. Join the parts per sender so the
                        // body matches what the inbox stores (and what the scan dedup key uses).
                        val receivedAtMs = System.currentTimeMillis()
                        messages.groupBy { it.originatingAddress ?: "" }.forEach { (sender, parts) ->
                            if (!isLikelyTransactionalSender(sender)) return@forEach

                            val body = parts.joinToString("") { it.messageBody ?: "" }
                            val sentAtMs = parts.first().timestampMillis

                            val parsed = parseSms(body, sentAtMs, receivedAtMs)
                            if (parsed != null) {
                                saveAndNotifyTransaction(context, parsed, sender)
                            }
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    // Known bank/UPI sender headers (without the region prefix, e.g. "HDFCBK" from "VM-HDFCBK")
    private val knownBankSenders = setOf(
        "HDFCBK", "ICICIB", "SBIINB", "SBIPSG", "AXISBK", "KOTAKB",
        "PAYTM", "PYTM", "GPAY", "PHONPE", "AMAZONP", "YESBNK",
        "CENTBK", "PNBSMS", "BOIIND", "UNIONB", "CANBNK", "IDFCFB",
        "SBIUPI", "ATMSBI", "SBICRD", "CBSSBI", "BOBTXN", "BOBSMS", "HSBCIN",
        "FEDBNK", "RBLBNK", "AUBANK", "INDUSB", "IDBIBK", "IOBCHN", "INDBNK",
        "UCOBNK", "KVBANK", "KARBNK", "SCBANK", "DBSBNK", "CITIBK", "ONECRD",
        "AMEXIN", "BOBCRD", "JUPITR", "FIBANK", "MOBIKW", "BHIMUPI"
    )

    private fun isLikelyTransactionalSender(sender: String): Boolean {
        val upperSender = sender.uppercase(Locale.ROOT)

        // Plain phone numbers (10+ digits) are never bank transactional senders
        if (upperSender.matches(Regex("^\\+?\\d{7,}$"))) return false

        // Check against known bank/UPI headers (match the code part, ignore prefix)
        val codePart = upperSender.substringAfter("-", upperSender)
        return (knownBankSenders.any { codePart.contains(it) })
    }

    private class ParsedTxn(
        val amount: Double,
        val merchant: String,
        val isDebit: Boolean,
        val date: String,
        val body: String,
        val sentAtMs: Long,
        val receivedAtMs: Long
    )

    private fun parseSms(body: String, sentAtMs: Long, receivedAtMs: Long): ParsedTxn? {
        val cleanBody = body.lowercase(Locale.ROOT)

        // 1. Drop marketing, OTPs and messages about payments that did not (yet) happen.
        //    Phrases only: single words like "free", "policy" or "https://" also appear
        //    in genuine debit SMS ("not you? visit https://...", insurance premium debits).
        if (NON_TRANSACTION_PHRASES.any { cleanBody.contains(it) }) return null
        if (OTP_PATTERN.containsMatchIn(cleanBody)) return null

        // 2. Require SPECIFIC transaction evidence — a masked account/card number
        //    or a real reference/txn id — not just the bare word "account"/"card"
        val hasMaskedAccountOrCard = Regex(
            "(?:a/c|acc(?:t|ount)?|card)\\s*(?:no\\.?|number)?\\s*[x*]{2,}\\d{2,}",
            RegexOption.IGNORE_CASE
        ).containsMatchIn(cleanBody)

        val hasTxnRef = Regex(
            "(?:ref|txn|transaction)\\s*(?:no|id)?[:.]?\\s*\\w{4,}",
            RegexOption.IGNORE_CASE
        ).containsMatchIn(cleanBody)

        val hasBalanceMention = cleanBody.contains("avl bal") ||
                cleanBody.contains("available balance") ||
                cleanBody.contains("bal:") ||
                cleanBody.contains("upi")

        val hasAccountEvidence = hasMaskedAccountOrCard || hasTxnRef || hasBalanceMention

        val debit = detectDirection(cleanBody) ?: return null
        if (!hasAccountEvidence) return null

        val amount = extractTransactionAmount(body) ?: return null

        // Extract merchant name
        var merchant = "Unknown Merchant"
        val merchantPatterns = arrayOf(
            Pattern.compile(
                "\\b(?:to|at|towards)\\s+([a-zA-Z0-9\\s\\.\\-\\*]+?)(?:\\s+on|\\s+ref|\\s+via|\\s+from|\\s+balance|\\.|\\n|$)",
                Pattern.CASE_INSENSITIVE
            ),
            Pattern.compile(
                "(?:info:?|vpa:?)\\s*([a-zA-Z0-9\\s\\.\\-\\*@]+?)(?:\\s+on|\\s+ref|\\.|\\n|$)",
                Pattern.CASE_INSENSITIVE
            )
        )

        for (pattern in merchantPatterns) {
            val matcher = pattern.matcher(body)
            if (matcher.find()) {
                val match = matcher.group(1)?.trim() ?: ""
                if (match.isNotEmpty() && match.length < 30) {
                    merchant = cleanMerchantName(match)
                    break
                }
            }
        }

        val df = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
        val dateStr = df.format(Date(receivedAtMs))

        return ParsedTxn(amount, merchant, debit, dateStr, body, sentAtMs, receivedAtMs)
    }

    /** true = debit, false = credit, null = not a transaction. Mirrors SmsParserService.detectDirection. */
    private fun detectDirection(lower: String): Boolean? {
        val d = STRONG_DEBIT.find(lower)
        val c = STRONG_CREDIT.find(lower)
        if (d != null && c != null) return d.range.first < c.range.first
        if (d != null) return true
        if (c != null) return false
        // Weaker verbs: refunds/receipts win over "payment of", so "payment of Rs X received"
        // (a card bill payment) and "refund for your payment" are credits.
        if (CREDIT_HINTS.containsMatchIn(lower)) return false
        if (DEBIT_HINTS.containsMatchIn(lower)) return true
        return null
    }

    /** First rupee amount that is not labelled as a balance or limit. */
    private fun extractTransactionAmount(body: String): Double? {
        for (m in AMOUNT_PATTERN.findAll(body)) {
            val before = body.substring(maxOf(0, m.range.first - 20), m.range.first)
            if (BALANCE_LABEL.containsMatchIn(before)) continue
            val value = m.groupValues[1].replace(",", "").toDoubleOrNull() ?: continue
            if (value > 0) return value
        }
        return null
    }

    private companion object {
        val NON_TRANSACTION_PHRASES = arrayOf(
            "pre-approved", "preapproved", "pre approved", "instant loan", "apply now",
            "loan offer", "credit limit enhance", "win up to", "you have won", "claim your reward",
            "click to apply", "download the app to claim", "buy now pay later", "shop now",
            "exclusive offer", "limited period offer", "unsubscribe",
            "declined", "has failed", "transaction failed", "unsuccessful",
            "could not be processed", "will be debited", "will be deducted", "is due on",
            "payment due", "minimum amount due", "total amount due", "has requested",
            "collect request", "is scheduled"
        )
        val OTP_PATTERN = Regex("\\b(?:otp|one[ -]time password|verification code)\\b")

        fun words(vararg w: String) = Regex("\\b(?:" + w.joinToString("|") { Regex.escape(it) } + ")\\b")
        val STRONG_DEBIT = words("debited", "debit of")
        val STRONG_CREDIT = words("credited", "credit of")
        val CREDIT_HINTS = words("refund", "refunded", "reversed", "reversal", "cashback", "received", "deposited")
        val DEBIT_HINTS = words("sent", "paid", "spent", "charged", "withdrawn", "withdrawal", "purchase", "txn of", "payment of", "used at")

        val AMOUNT_PATTERN = Regex("(?:rs|inr|rupees?|₹)\\.?\\s*:?\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)", RegexOption.IGNORE_CASE)
        val BALANCE_LABEL = Regex("(?:bal(?:ance)?|limit|lmt)[^0-9]{0,12}$", RegexOption.IGNORE_CASE)
    }

    private fun cleanMerchantName(name: String): String {
        var cleaned = name.replace(Regex("\\s+"), " ").trim()
        if (cleaned.contains("@")) {
            cleaned = cleaned.split("@")[0]
        }

        // Capitalize words
        val words = cleaned.split(" ")
        val capitalized = StringBuilder()
        for (w in words) {
            if (w.isNotEmpty()) {
                capitalized.append(w.substring(0, 1).uppercase(Locale.ROOT))
                if (w.length > 1) {
                    capitalized.append(w.substring(1).lowercase(Locale.ROOT))
                }
                capitalized.append(" ")
            }
        }
        return capitalized.toString().trim()
    }

    private fun saveAndNotifyTransaction(context: Context, txn: ParsedTxn, sender: String) {
        val txnMap = hashMapOf<String, Any>(
            "amount" to txn.amount,
            "merchant" to txn.merchant,
            "isDebit" to txn.isDebit,
            "date" to txn.date,
            "body" to txn.body,
            "source" to "sms",
            "sender" to sender,
            "sentAtMs" to txn.sentAtMs,
            "receivedAtMs" to txn.receivedAtMs
        )

        // 1. Queue it so Flutter saves it even if the app is not running
        val id = java.util.UUID.randomUUID().toString()
        txnMap["id"] = id
        try {
            PendingSmsStore.add(context, JSONObject().apply {
                put("id", id)
                put("amount", txn.amount)
                put("merchant", txn.merchant)
                put("isDebit", txn.isDebit)
                put("date", txn.date)
                put("body", txn.body)
                put("source", "sms")
                put("sender", sender)
                put("sentAtMs", txn.sentAtMs)
                put("receivedAtMs", txn.receivedAtMs)
            })
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // 2. Notify live MainActivity if open
        MainActivity.onLiveTransactionCaptured(txnMap)

        // 3. Post notification informing user that transaction was auto-saved
        showNotification(context, txn, sender)
    }

    private fun showNotification(context: Context, txn: ParsedTxn, sender: String) {
        val channelId = "fiscora_sms_capture"
        val notificationId = System.currentTimeMillis().toInt()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Fiscora Auto-Capture",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts for incoming transaction SMS"
            }
            manager.createNotificationChannel(channel)
        }

        // Tap opens MainActivity
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("amount", txn.amount)
            putExtra("merchant", txn.merchant)
            putExtra("isDebit", txn.isDebit)
            putExtra("date", txn.date)
            putExtra("body", txn.body)
            putExtra("source", "sms")
            putExtra("sender", sender)
            putExtra("sentAtMs", txn.sentAtMs)
            putExtra("receivedAtMs", txn.receivedAtMs)
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            pendingIntentFlags
        )

        val direction = if (txn.isDebit) "debited" else "credited"
        val message = String.format(
            Locale.ROOT,
            "₹%.2f %s at %s. Open Fiscora to review.",
            txn.amount,
            direction,
            txn.merchant
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_menu_my_calendar)
            .setContentTitle("Transaction captured")
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        manager.notify(notificationId, builder.build())
    }
}
