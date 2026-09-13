package com.kammcs.boardhop

import android.content.Context
import android.util.Log
import com.microsoft.identity.client.AcquireTokenSilentParameters
import com.microsoft.identity.client.IMultipleAccountPublicClientApplication
import com.microsoft.identity.client.IPublicClientApplication
import com.microsoft.identity.client.MultipleAccountPublicClientApplication
import com.microsoft.identity.client.exception.MsalException
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * An Azure DevOps access token for the account that registered one
 * organization, acquired **silently** inside the messaging service
 * (research/14 §4.1, "Token").
 *
 * How the service reaches MSAL without a second client id anywhere:
 *
 * * **Configuration.** `packages/msal_auth`'s Android side writes the whole
 *   MSAL config — client id, authority, redirect URI, `account_mode: MULTIPLE`,
 *   `client_capabilities: CP1` — to `cacheDir/msal_config.json` every time
 *   Dart creates the public client application, which is every app start
 *   (`MsalAuthHandler.onMethodCall`, `createMultipleAccountPca`). This class
 *   reads that file and mirrors it to `filesDir/boardhop_msal_config.json`, so
 *   a push that arrives after Android has cleared the cache directory still
 *   has a configuration to build on. Nothing is copied off the device and the
 *   client id is never logged.
 * * **Account.** `PushRegistrar` stores the MSAL account identifier of the
 *   account that registered each organization in shared preferences under
 *   `push.msal.account.{org}` (the `flutter.` prefix is what
 *   `shared_preferences` uses on Android), and that identifier is exactly what
 *   `IMultipleAccountPublicClientApplication.getAccount` takes.
 * * **Cache.** The service runs in the app's own process, so MSAL's token
 *   cache is the same one the app uses; a second `PublicClientApplication` on
 *   the same configuration shares it.
 *
 * Anything at all going wrong — no configuration, no account, an expired
 * refresh token, `MsalUiRequiredException`, Conditional Access — returns null
 * and the caller posts the fallback line. Interaction is never attempted from
 * here; the app raises `AuthInteractionRequired` the next time it is opened,
 * as it does today.
 */
object PushTokens {

    /** research/09: the Azure DevOps resource. */
    const val ADO_SCOPE = "499b84ac-1321-427f-aa17-267ca6975798/.default"

    private const val TAG = PushEnricher.TAG
    private const val PLUGIN_CONFIG = "msal_config.json"
    private const val MIRRORED_CONFIG = "boardhop_msal_config.json"

    @Volatile
    private var pca: IMultipleAccountPublicClientApplication? = null

    /** `flutter.push.msal.account.{org}` in `FlutterSharedPreferences`. */
    fun accountIdFor(context: Context, org: String): String? = try {
        context
            .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.push.msal.account.$org", null)
            ?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    /**
     * A token for [org], or null. Blocks; call it from a worker thread (MSAL's
     * synchronous API refuses the main thread, and so does this).
     */
    fun tokenFor(context: Context, org: String, deadline: Long): String? {
        val accountId = accountIdFor(context, org)
        if (accountId == null) {
            Log.d(TAG, "token: no registered account for this org")
            return null
        }
        val client = client(context, deadline) ?: return null
        return try {
            val account = client.getAccount(accountId)
            if (account == null) {
                Log.d(TAG, "token: the registered account is no longer in the MSAL cache")
                return null
            }
            val parameters = AcquireTokenSilentParameters.Builder()
                .withScopes(listOf(ADO_SCOPE))
                .forAccount(account)
                .fromAuthority(account.authority)
                .build()
            val result = client.acquireTokenSilent(parameters)
            Log.d(TAG, "token: acquired silently")
            result.accessToken
        } catch (e: MsalException) {
            // MsalUiRequiredException and everything else alike: fallback line.
            Log.d(TAG, "token: silent acquisition failed (${e.javaClass.simpleName})")
            null
        } catch (e: Exception) {
            Log.d(TAG, "token: ${e.javaClass.simpleName}")
            null
        }
    }

    private fun client(context: Context, deadline: Long): IMultipleAccountPublicClientApplication? {
        pca?.let { return it }
        val config = configFile(context) ?: run {
            Log.d(TAG, "token: no MSAL configuration on disk")
            return null
        }
        val latch = CountDownLatch(1)
        var created: IMultipleAccountPublicClientApplication? = null
        MultipleAccountPublicClientApplication.createMultipleAccountPublicClientApplication(
            context.applicationContext,
            config,
            object : IPublicClientApplication.IMultipleAccountApplicationCreatedListener {
                override fun onCreated(application: IMultipleAccountPublicClientApplication) {
                    created = application
                    latch.countDown()
                }

                override fun onError(exception: MsalException) {
                    Log.d(TAG, "token: PCA creation failed (${exception.javaClass.simpleName})")
                    latch.countDown()
                }
            },
        )
        val remaining = deadline - android.os.SystemClock.elapsedRealtime()
        if (remaining <= 0 || !latch.await(remaining, TimeUnit.MILLISECONDS)) {
            Log.d(TAG, "token: PCA creation did not finish inside the budget")
            return null
        }
        pca = created
        return created
    }

    /**
     * The plugin's configuration if it is still in the cache directory,
     * otherwise this service's mirror of it. Reading the live one refreshes
     * the mirror.
     */
    private fun configFile(context: Context): File? {
        val mirror = File(context.filesDir, MIRRORED_CONFIG)
        val live = File(context.cacheDir, PLUGIN_CONFIG)
        if (live.isFile && live.length() > 0) {
            try {
                if (!mirror.isFile || mirror.lastModified() < live.lastModified()) {
                    live.copyTo(mirror, overwrite = true)
                }
            } catch (_: Exception) {
                // A mirror that cannot be written is not worth failing over.
            }
            return live
        }
        return mirror.takeIf { it.isFile && it.length() > 0 }
    }
}
