package com.surya.fiscora

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Queue of captured SMS transactions waiting for Flutter to save them.
 *
 * Every read-modify-write runs under one lock, and Flutter removes items by id
 * after it has handled them, so an SMS that arrives while Flutter is processing
 * the queue is never wiped by a blanket "clear".
 */
object PendingSmsStore {
    private const val PREFS = "fiscora_sms_prefs"
    private const val KEY = "pending_transactions"
    private val lock = Any()

    fun add(context: Context, txn: JSONObject) {
        synchronized(lock) {
            val array = read(context)
            if (!txn.has("id")) txn.put("id", UUID.randomUUID().toString())
            array.put(txn)
            write(context, array)
        }
    }

    /** Returns all queued items, giving legacy items (queued before ids existed) an id. */
    fun list(context: Context): List<HashMap<String, Any>> {
        synchronized(lock) {
            val array = read(context)
            var changed = false
            val result = ArrayList<HashMap<String, Any>>()
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                if (!obj.has("id")) {
                    obj.put("id", UUID.randomUUID().toString())
                    changed = true
                }
                result.add(toMap(obj))
            }
            if (changed) write(context, array)
            return result
        }
    }

    fun remove(context: Context, ids: Collection<String>) {
        if (ids.isEmpty()) return
        synchronized(lock) {
            val array = read(context)
            val kept = JSONArray()
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                if (obj.optString("id") !in ids) kept.put(obj)
            }
            write(context, kept)
        }
    }

    private fun read(context: Context): JSONArray {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, "[]") ?: "[]"
        return try { JSONArray(json) } catch (e: Exception) { JSONArray() }
    }

    // commit() rather than apply(): the receiver process can be killed right after onReceive.
    private fun write(context: Context, array: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, array.toString()).commit()
    }

    private fun toMap(obj: JSONObject): HashMap<String, Any> {
        val map = HashMap<String, Any>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            when (val value = obj.get(key)) {
                is Double -> map[key] = value
                is Long -> map[key] = value
                is Int -> map[key] = if (key.endsWith("AtMs")) value.toLong() else value.toDouble()
                is Boolean -> map[key] = value
                else -> map[key] = value.toString()
            }
        }
        return map
    }
}
