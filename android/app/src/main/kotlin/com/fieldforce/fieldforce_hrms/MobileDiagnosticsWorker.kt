package com.fieldforce.fieldforce_hrms

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

object MobileDiagnosticsScheduler {
    fun schedule(context:Context) {
        val network=Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val manager=WorkManager.getInstance(context)
        manager.enqueueUniqueWork("trackyu-diagnostics-now",ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<MobileDiagnosticsWorker>().setConstraints(network)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL,30,TimeUnit.SECONDS).build())
        manager.enqueueUniquePeriodicWork("trackyu-diagnostics-periodic",ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<MobileDiagnosticsWorker>(15,TimeUnit.MINUTES).setConstraints(network).build())
    }
}
class MobileDiagnosticsWorker(context:Context,params:WorkerParameters):Worker(context,params) {
    override fun doWork():Result=try {
        if(MobileDiagnostics.upload(applicationContext,TrackingRuntime.store(applicationContext)))Result.success() else Result.retry()
    }catch(_:Exception){Result.retry()}
}
