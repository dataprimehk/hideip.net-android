package net.hideip.vpn

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-bound authenticated encryption for the Always-on tunnel config. */
internal object ConfigVault {
    private const val KEY_ALIAS = "hideip_always_on_config_v1"
    private const val VERSION: Byte = 1
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    fun write(file: File, clearText: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(clearText.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        require(iv.size in 1..255) { "Invalid AES-GCM nonce" }
        val payload = ByteArray(2 + iv.size + encrypted.size)
        payload[0] = VERSION
        payload[1] = iv.size.toByte()
        iv.copyInto(payload, 2)
        encrypted.copyInto(payload, 2 + iv.size)

        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try {
            output.write(payload)
            output.fd.sync()
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            atomic.failWrite(output)
            throw error
        }
    }

    fun read(file: File): String? {
        if (!file.exists()) return null
        val payload = AtomicFile(file).readFully()
        if (payload.size < 3 || payload[0] != VERSION) return null
        val ivSize = payload[1].toInt() and 0xff
        if (ivSize == 0 || payload.size <= 2 + ivSize) return null
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(128, payload.copyOfRange(2, 2 + ivSize)),
        )
        val clear = cipher.doFinal(payload.copyOfRange(2 + ivSize, payload.size))
        return clear.toString(Charsets.UTF_8)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }
}
