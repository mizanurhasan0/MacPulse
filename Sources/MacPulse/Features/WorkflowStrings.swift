import Foundation

enum WorkflowKey: String, CaseIterable {
    case storageAvailableSpace, storageUsedPercent, storageUsedOfTotal, storageCategories
    case storageCacheSummary, storageLargeSummary, storageDuplicateSummary
    case storageCacheIntro, storageLargeIntro, storageDuplicateIntro
    case storageReadyTitle, storageReadyDetail, storageReadOnly, storageProtectedHint
    case storageResults, storageCacheSummaryCount, storageFolderLabel
    case storageFolderFilesSummary, storageFolderFilesAggregate
    case expandFolder, collapseFolder, folderSelectionHint, folderSelectionState
    case folderPartiallySelected, bulkSelectionKeepsCopy
    case folderNotSelected
    case parallelWorkers, reusedHashProgress, scanPerformance, reuseFingerprints, reuseFingerprintsDetails
    case clearScanMemory, scanMemoryCleared
    case scanLargeFiles, scanDuplicates, precheckingFiles, duplicateScanNeeded, hashBytesProgress
    case comparedBytesProgress, candidatesProgress, fileLimitReached, largeResultsReady, listedSummary
    case duplicateVerificationPending
    case stopRequested, measurementWindows
    case cacheTab, largeTab, duplicatesTab, chooseFolder, scanFolder, folderPrompt, largeThreshold
    case scanEmpty, scanFinished, scanSkipped, operationCancelled, cancelWork, previewSelected, moveToTrash
    case trashWarning, cleanupReview, cleanupReviewIntro, selectedCount, estimatedMoved, revealFinder
    case retainedCopy, exactDuplicates, noLargeFiles, noDuplicates, scannedSummary
    case scanEnumerating, scanHashing, scanVerifying, fileScanIntro, keepAtLeastOne
    case appRunningCache, protectedCache, incompleteCache, freshScanRequired, modified, filePath
    case boostReview, boostIntro, boostApplications, boostCaches, boostAdvice, noEligibleApps, noEligibleCaches
    case executePlan, verifyBefore, applyingActions, verifyAfter, progressCount, boostResults, observedResults
    case before, after, observedChange, availableMemory, availableDisk, applicationCount, cpuWindow
    case noMeasurement, resultsWarning, cancelExplanation, done, retry, viewStorage, openTrash
    case successMoved, successQuit, stillWaiting, requestRejected, identityChanged, actionCancelled, actionFailed
    case details, snoozeHour, restoreRecommendations, cacheCleanupHistory, fileScanHistory, fileCleanupHistory,
        boostHistory
    case failedStatus, partialStatus, cancelledStatus, itemNoLongerExists, finderUnavailable, operationFailed
    case scanCancelledPartial, cacheRebuildWarning, fileCleanupWarning, nothingSelected, reviewSafety
    case cpuPerCore, processResources, historyOperationCount, swapNowAvailable, refreshVersions
    case developerChecking, developerVersions, developerTimeout, developerUnavailable, developerReadOnly
    case keepThisCopy
    case protectedFile, historyItemCount
    case recentActivity, memoryAvailablePercent, collectingSamples
    case runningContainers, stoppedContainers, dockerImages, quitHistory, notChecked
    case developerProcesses, inspectProcesses, stopProcess, stopProcessWarning, noDeveloperProcesses,
        developerStopHistory
}

@MainActor extension LocalizationStore {
    func workflow(_ key: WorkflowKey, _ arguments: CVarArg...) -> String {
        let values = workflowTranslations[key] ?? (key.rawValue, key.rawValue, key.rawValue)
        let value: String =
            switch language {
            case .english: values.0
            case .bangla: values.1
            case .arabic: values.2
            }
        return arguments.isEmpty ? value : String(format: value, locale: language.locale, arguments: arguments)
    }
}

let workflowTranslations: [WorkflowKey: (String, String, String)] = [
    .storageAvailableSpace: ("Available space", "খালি জায়গা", "المساحة المتاحة"),
    .storageUsedPercent: ("%d%% used", "%d%% ব্যবহৃত", "%d%% مستخدم"),
    .storageUsedOfTotal: ("%@ used of %@", "%@ ব্যবহৃত · মোট %@", "%@ مستخدم من %@"),
    .storageCategories: ("Scan categories", "স্ক্যানের ধরন", "أنواع الفحص"),
    .storageCacheSummary: ("Review app cache folders", "অ্যাপের cache ফোল্ডার দেখুন", "راجع مجلدات ذاكرة التطبيقات"),
    .storageLargeSummary: ("Find what takes up space", "বেশি জায়গা নেওয়া ফাইল খুঁজুন", "اعثر على الملفات التي تشغل مساحة"),
    .storageDuplicateSummary: ("Compare identical copies", "একই ফাইলের কপি যাচাই করুন", "قارن النسخ المتطابقة"),
    .storageCacheIntro: (
        "See cache sizes and protection status before deciding what to remove.",
        "সরানোর সিদ্ধান্তের আগে cache-এর আকার ও সুরক্ষার অবস্থা দেখুন।",
        "اطّلع على أحجام الذاكرة المؤقتة وحالة حمايتها قبل اختيار ما تريد إزالته."
    ),
    .storageLargeIntro: (
        "Choose a folder and a minimum size to find files worth reviewing.",
        "বড় ফাইল খুঁজতে ফোল্ডার ও ফাইলের ন্যূনতম আকার বেছে নিন।",
        "اختر مجلداً وحداً أدنى للحجم للعثور على ملفات تستحق المراجعة."
    ),
    .storageDuplicateIntro: (
        "Find matching files in a folder you choose. Keep one copy and review the rest.",
        "নিজের বেছে নেওয়া ফোল্ডারে একই ফাইলের কপি খুঁজুন। একটি রেখে বাকি কপি যাচাই করুন।",
        "اعثر على الملفات المتطابقة في مجلد تختاره. احتفظ بنسخة وراجع البقية."
    ),
    .storageReadyTitle: ("Ready for a closer look", "স্ক্যান শুরু করতে প্রস্তুত", "جاهز لإلقاء نظرة أقرب"),
    .storageReadyDetail: (
        "Your results will appear here after a scan. You choose what happens next.",
        "স্ক্যানের পর ফল এখানে দেখা যাবে। এরপর কী করবেন, তা আপনি বেছে নেবেন।",
        "ستظهر النتائج هنا بعد الفحص. أنت تختار الخطوة التالية."
    ),
    .storageReadOnly: ("Scan first. Review before cleaning.", "আগে স্ক্যান, পরিষ্কারের আগে যাচাই।", "افحص أولاً، وراجع قبل التنظيف."),
    .storageProtectedHint: (
        "Active app caches and protected folders are excluded. Apps may rebuild cleared caches.",
        "চলমান অ্যাপের cache ও সুরক্ষিত ফোল্ডার বাদ যায়। পরিষ্কার করা cache অ্যাপ আবার তৈরি করতে পারে।",
        "تُستبعد ذاكرة التطبيقات النشطة والمجلدات المحمية. قد تعيد التطبيقات بناء الذاكرة التي تُمسح."
    ),
    .storageResults: ("Scan results", "স্ক্যানের ফলাফল", "نتائج الفحص"),
    .storageCacheSummaryCount: ("%d folders · %@ analyzed", "%dটি ফোল্ডার · %@ বিশ্লেষিত", "%d مجلداً · حُلّل %@"),
    .storageFolderLabel: ("Selected folder", "নির্বাচিত ফোল্ডার", "المجلد المحدد"),
    .storageFolderFilesSummary: (
        "%d files · %d selectable · %d selected", "%dটি ফাইল · %dটি নির্বাচনযোগ্য · %dটি নির্বাচিত",
        "%d ملفات · %d قابلة للتحديد · %d محددة"
    ),
    .storageFolderFilesAggregate: (
        "%d folders · %d files · %@ total", "%dটি ফোল্ডার · %dটি ফাইল · মোট %@",
        "%d مجلدات · %d ملفات · الإجمالي %@"
    ),
    .expandFolder: ("Show files", "ফাইল দেখুন", "اعرض الملفات"),
    .collapseFolder: ("Hide files", "ফাইল লুকান", "أخفِ الملفات"),
    .folderSelectionHint: (
        "Select eligible files inside this folder. The folder stays in place; known verified duplicates keep one copy.",
        "ফোল্ডারের ভেতরের নির্বাচনযোগ্য ফাইল বাছুন। ফোল্ডারটি থাকবে, আর পরিচিত যাচাইকৃত duplicate থেকে একটি কপি রাখা হবে।",
        "حدد الملفات المؤهلة داخل هذا المجلد. يبقى المجلد كما هو، وتُحفظ نسخة من التكرارات المؤكدة المعروفة."
    ),
    .folderSelectionState: ("Selected", "নির্বাচিত", "محدد"),
    .folderPartiallySelected: ("Partially selected", "কিছু নির্বাচিত", "محدد جزئياً"),
    .folderNotSelected: ("Not selected", "নির্বাচিত নয়", "غير محدد"),
    .bulkSelectionKeepsCopy: (
        "Select a folder to choose its eligible files. Each folder stays in place; known duplicate sets keep one copy. Expand to review individual files.",
        "ফোল্ডার বাছলে তার নির্বাচনযোগ্য ফাইলগুলো চিহ্নিত হয়; ফোল্ডারটি থাকে। পরিচিত duplicate থেকে একটি কপি রাখা হয়। আলাদা ফাইল দেখতে ফোল্ডার খুলুন।",
        "حدد مجلداً لاختيار ملفاته المؤهلة. يبقى المجلد كما هو وتُحفظ نسخة من التكرارات المعروفة. افتحه لمراجعة الملفات فردياً."
    ),
    .parallelWorkers: ("Up to %d scan workers", "সর্বোচ্চ %dটি scan worker", "حتى %d من مهام الفحص المتزامنة"),
    .reusedHashProgress: (
        "%@ read · %@ reused · %@ planned", "%@ পড়া · %@ পুনর্ব্যবহার · মোট %@", "قُرئ %@ · أُعيد استخدام %@ · المخطط %@"
    ),
    .scanPerformance: ("File scanning", "ফাইল স্ক্যান", "فحص الملفات"),
    .reuseFingerprints: ("Faster repeat scans", "পুনরায় দ্রুত স্ক্যান", "تسريع الفحوص المتكررة"),
    .reuseFingerprintsDetails: (
        "Reuses in-memory fingerprints for up to 10 minutes on internal disks. Changed files are read again, and duplicates always receive a full byte comparison. Nothing is saved to disk. Workers reduce automatically under heat or Low Power Mode.",
        "অভ্যন্তরীণ ডিস্কের fingerprint সর্বোচ্চ ১০ মিনিট মেমরি থেকে পুনর্ব্যবহার করে। পরিবর্তিত ফাইল আবার পড়ে এবং duplicate সবসময় পুরো byte তুলনা করে যাচাই হয়। ডিস্কে কিছু সংরক্ষিত হয় না। গরম বা Low Power Mode-এ worker স্বয়ংক্রিয়ভাবে কমে।",
        "تُعاد الاستفادة من البصمات في الذاكرة حتى 10 دقائق للأقراص الداخلية. تُقرأ الملفات المتغيرة مجدداً، وتُقارن النسخ دائماً بايتاً بايتاً. لا يُحفظ شيء على القرص. ينخفض التوازي تلقائياً عند الحرارة أو وضع الطاقة المنخفضة."
    ),
    .clearScanMemory: ("Clear scan memory", "স্ক্যান মেমরি মুছুন", "امسح ذاكرة الفحص"),
    .scanMemoryCleared: ("Scan memory cleared.", "স্ক্যান মেমরি মোছা হয়েছে।", "مُسحت ذاكرة الفحص."),
    .duplicateVerificationPending: (
        "Duplicate verification is still running. Large-file results are already available in the Large files tab.",
        "Duplicate যাচাই চলছে। Large files tab-এ বড় ফাইলের ফল এখনই দেখা যাবে।",
        "لا يزال التحقق من النسخ جارياً. نتائج الملفات الكبيرة متاحة الآن في علامة تبويب الملفات الكبيرة."
    ),
    .scanLargeFiles: ("Find large files", "বড় ফাইল খুঁজুন", "ابحث عن الملفات الكبيرة"),
    .scanDuplicates: ("Find duplicates", "একই ফাইলের কপি খুঁজুন", "ابحث عن النسخ المكررة"),
    .precheckingFiles: (
        "Quick-checking matching file sizes…", "একই আকারের ফাইল প্রাথমিকভাবে যাচাই হচ্ছে…", "جارٍ فحص أولي للملفات متساوية الحجم…"
    ),
    .duplicateScanNeeded: (
        "Duplicate checking has not run. Choose Find duplicates to verify matching content.",
        "Duplicate যাচাই এখনও হয়নি। একই ডেটা যাচাই করতে কপি খোঁজার scan চালান।",
        "لم يُجرَ فحص النسخ المكررة. اختر البحث عنها للتحقق من تطابق المحتوى."
    ),
    .hashBytesProgress: (
        "Read %@ of %@ for full hashing", "পূর্ণ hash-এর জন্য %@ / %@ পড়া হয়েছে", "قُرئ %@ من %@ للحساب الكامل للبصمات"
    ),
    .comparedBytesProgress: ("%@ compared byte by byte", "%@ byte-by-byte তুলনা হয়েছে", "قورنت %@ بايتاً بايتاً"),
    .candidatesProgress: (
        "%d of %d candidate files checked", "%d / %dটি candidate ফাইল যাচাই হয়েছে", "فُحص %d من %d ملفات مرشحة"
    ),
    .fileLimitReached: (
        "The %d-file limit was reached. These results cover only part of the folder. Choose a smaller subfolder for a complete scan.",
        "%dটি ফাইলের সীমায় পৌঁছেছে। এই ফল ফোল্ডারের এক অংশের। সম্পূর্ণ scan-এর জন্য ছোট subfolder বেছে নিন।",
        "بُلِغ حد %d ملفاً. تغطي النتائج جزءاً من المجلد فقط. اختر مجلداً فرعياً أصغر لفحص كامل."
    ),
    .largeResultsReady: (
        "Large-file results are ready below. Duplicate verification is still running; Cancel stops that work and keeps the file listing.",
        "বড় ফাইলের ফল নিচে প্রস্তুত। Duplicate যাচাই চলছে; Cancel করলে সেটি থেমে ফাইলের তালিকা থাকবে।",
        "نتائج الملفات الكبيرة جاهزة أدناه. لا يزال التحقق من النسخ يعمل؛ يوقفه الإلغاء مع الاحتفاظ بقائمة الملفات."
    ),
    .listedSummary: (
        "%d files listed · %d items skipped", "%dটি ফাইল তালিকাভুক্ত · %dটি আইটেম বাদ", "أُدرج %d ملفاً · تُخطي %d عنصراً"
    ),
    .stopRequested: (
        "Stop request sent; exit was not verified", "বন্ধের অনুরোধ পাঠানো হয়েছে; বন্ধ হওয়া যাচাই হয়নি",
        "أُرسل طلب الإيقاف ولم يُتحقق من الخروج"
    ),
    .measurementWindows: (
        "CPU windows: %.1f s (%d samples) before · %.1f s (%d samples) after",
        "CPU পরিমাপ: আগে %.1f সেকেন্ড (%dটি sample) · পরে %.1f সেকেন্ড (%dটি sample)",
        "نافذتا CPU: قبل %.1f ث (%d عينات) · بعد %.1f ث (%d عينات)"
    ),
    .keepThisCopy: ("Keep this copy", "এই কপি রাখুন", "احتفظ بهذه النسخة"),
    .developerProcesses: ("Development processes", "ডেভেলপমেন্ট প্রসেস", "عمليات التطوير"),
    .inspectProcesses: ("Inspect Node / Bun / Deno", "Node / Bun / Deno দেখুন", "افحص Node / Bun / Deno"),
    .stopProcess: ("Stop process…", "প্রসেস বন্ধ করুন…", "أوقف العملية…"),
    .stopProcessWarning: (
        "Stopping a development process can interrupt requests, builds, and unsaved work. Only a graceful stop is attempted; it is never forced.",
        "ডেভেলপমেন্ট প্রসেস বন্ধ করলে request, build ও অসংরক্ষিত কাজ থামতে পারে। শুধু স্বাভাবিকভাবে বন্ধের চেষ্টা হবে; জোর করে বন্ধ হবে না।",
        "قد يقطع إيقاف عملية تطوير الطلبات والبناء والعمل غير المحفوظ. ستُجرّب محاولة إيقاف طبيعية فقط ولن يُفرض الإنهاء."
    ),
    .noDeveloperProcesses: (
        "No eligible Node, Bun, or Deno processes were found.", "উপযুক্ত Node, Bun বা Deno প্রসেস নেই।",
        "لم يُعثر على عمليات Node أو Bun أو Deno مؤهلة."
    ),
    .developerStopHistory: ("Development process stop", "ডেভেলপমেন্ট প্রসেস বন্ধ", "إيقاف عملية تطوير"),
    .runningContainers: ("Running containers", "চলমান container", "الحاويات العاملة"),
    .stoppedContainers: ("Stopped containers", "বন্ধ container", "الحاويات المتوقفة"),
    .dockerImages: ("Images", "ইমেজ", "الصور"),
    .quitHistory: ("Graceful app quit", "স্বাভাবিকভাবে অ্যাপ বন্ধ", "إنهاء طبيعي للتطبيق"),
    .notChecked: ("Not checked yet", "এখনও যাচাই হয়নি", "لم يُفحص بعد"),
    .recentActivity: ("Recent activity", "সাম্প্রতিক কার্যকলাপ", "النشاط الأخير"),
    .memoryAvailablePercent: ("Estimated available memory (%)", "আনুমানিক খালি মেমরি (%)", "الذاكرة المتاحة المقدرة (%)"),
    .collectingSamples: ("Collecting interval samples…", "সময়ের ব্যবধানে sample নেওয়া হচ্ছে…", "جارٍ جمع عينات زمنية…"),
    .protectedFile: ("Protected file · reveal only", "সুরক্ষিত ফাইল · শুধু দেখা যাবে", "ملف محمي · للعرض فقط"),
    .historyItemCount: ("%d items", "%dটি আইটেম", "%d عناصر"),
    .cacheTab: ("App caches", "অ্যাপের cache", "ذاكرة التطبيقات المؤقتة"),
    .largeTab: ("Large files", "বড় ফাইল", "الملفات الكبيرة"),
    .duplicatesTab: ("Duplicates", "একই ফাইলের কপি", "الملفات المكررة"),
    .chooseFolder: ("Choose folder…", "ফোল্ডার বেছে নিন…", "اختر مجلداً…"),
    .scanFolder: ("Scan folder", "ফোল্ডার স্ক্যান", "افحص المجلد"),
    .folderPrompt: (
        "Choose a folder to analyze. Scanning does not change its files.", "বিশ্লেষণের জন্য ফোল্ডার বেছে নিন। স্ক্যানে ফাইল বদলায় না।",
        "اختر مجلداً لتحليله. لا يغيّر الفحص ملفاته."
    ),
    .largeThreshold: ("Minimum file size (MiB)", "ফাইলের সর্বনিম্ন আকার (MiB)", "الحد الأدنى لحجم الملف (MiB)"),
    .scanEmpty: ("No eligible items were found.", "উপযুক্ত কোনো আইটেম পাওয়া যায়নি।", "لم يُعثر على عناصر مؤهلة."),
    .scanFinished: (
        "Scan complete. Review the results below.", "স্ক্যান শেষ। নিচের ফলাফল যাচাই করুন।", "اكتمل الفحص. راجع النتائج أدناه."
    ),
    .scanSkipped: (
        "Scan complete with skipped items. Results may be incomplete.", "কিছু আইটেম বাদ দিয়ে স্ক্যান শেষ। ফলাফল অসম্পূর্ণ হতে পারে।",
        "اكتمل الفحص مع تخطي عناصر. قد تكون النتائج غير مكتملة."
    ),
    .operationCancelled: (
        "Cancelled. Completed actions remain in the results.", "বাতিল হয়েছে। সম্পন্ন কাজ ফলাফলে থাকবে।",
        "تم الإلغاء. تبقى الإجراءات المكتملة ضمن النتائج."
    ),
    .cancelWork: ("Cancel remaining work", "বাকি কাজ বাতিল", "ألغِ العمل المتبقي"),
    .previewSelected: ("Review selected…", "নির্বাচিত আইটেম যাচাই…", "راجع المحدد…"),
    .moveToTrash: ("Move to Trash", "Trash-এ পাঠান", "انقل إلى سلة المهملات"),
    .trashWarning: (
        "Moving to Trash keeps data recoverable and usually does not free disk space immediately. Restore items from Finder if needed. MacPulse will not empty Trash.",
        "Trash-এ রাখা ডেটা ফেরত আনা যায়; সাধারণত সঙ্গে সঙ্গে disk space খালি হয় না। প্রয়োজনে Finder থেকে ফিরিয়ে নিন। MacPulse Trash খালি করবে না।",
        "يمكن استعادة البيانات المنقولة إلى السلة، ولا تُحرر المساحة عادةً فوراً. استعد العناصر من Finder عند الحاجة. لن يفرغ MacPulse السلة."
    ),
    .cleanupReview: ("Review cleanup", "পরিষ্কার করার আগে যাচাই", "مراجعة التنظيف"),
    .cleanupReviewIntro: (
        "Only the listed items will be moved. Check each path before approving.",
        "শুধু তালিকার আইটেম সরানো হবে। অনুমোদনের আগে প্রতিটি পথ দেখুন।", "ستُنقل العناصر المدرجة فقط. تحقق من كل مسار قبل الموافقة."
    ),
    .selectedCount: ("%d selected", "%dটি নির্বাচিত", "تم تحديد %d"),
    .estimatedMoved: ("Estimated data moved", "সরানো ডেটার আনুমানিক আকার", "حجم البيانات المنقولة التقديري"),
    .revealFinder: ("Show in Finder", "Finder-এ দেখুন", "اعرض في Finder"),
    .retainedCopy: ("Kept copy", "যে কপিটি রাখা হবে", "النسخة المحتفظ بها"),
    .exactDuplicates: ("Exact duplicate groups", "হুবহু একই ফাইলের গ্রুপ", "مجموعات النسخ المتطابقة"),
    .noLargeFiles: ("No files meet the size threshold.", "নির্ধারিত আকারের ফাইল নেই।", "لا توجد ملفات تبلغ حد الحجم."),
    .noDuplicates: ("No verified duplicates found.", "যাচাইকৃত একই ফাইলের কপি নেই।", "لم يُعثر على نسخ مكررة مؤكدة."),
    .scannedSummary: ("%d files scanned · %d items skipped", "%dটি ফাইল স্ক্যান · %dটি আইটেম বাদ", "فُحص %d ملفاً · تُخطي %d عنصراً"),
    .scanEnumerating: ("Reading file information…", "ফাইলের তথ্য পড়া হচ্ছে…", "جارٍ قراءة معلومات الملفات…"),
    .scanHashing: ("Comparing file fingerprints…", "ফাইলের fingerprint তুলনা হচ্ছে…", "جارٍ مقارنة بصمات الملفات…"),
    .scanVerifying: ("Verifying identical content…", "একই ডেটা যাচাই হচ্ছে…", "جارٍ التحقق من تطابق المحتوى…"),
    .fileScanIntro: (
        "Large-file scans read file information only. Duplicate scans separately quick-check candidates, then verify full SHA-256 and bytes. Hidden items, packages, dependency folders, protected files, links and cloud placeholders are excluded from duplicate checks.",
        "বড় ফাইলের scan শুধু file information পড়ে। Duplicate scan আলাদাভাবে প্রাথমিক যাচাইয়ের পর পূর্ণ SHA-256 ও byte মেলায়। লুকানো আইটেম, package, dependency folder, সুরক্ষিত file, link ও cloud placeholder বাদ যায়।",
        "يقرأ فحص الملفات الكبيرة معلوماتها فقط. يفحص البحث عن النسخ المرشحين أولياً ثم يتحقق من SHA-256 الكامل والبايتات. تُستبعد العناصر المخفية والحزم ومجلدات التبعيات والملفات المحمية والروابط وعناصر السحابة."
    ),
    .keepAtLeastOne: (
        "One verified copy is always kept. Nothing is selected automatically.",
        "অন্তত একটি যাচাইকৃত কপি রাখা হবে। স্বয়ংক্রিয়ভাবে কিছু নির্বাচন হয় না।", "تُحفظ دائماً نسخة مؤكدة واحدة. لا يُحدد أي شيء تلقائياً."
    ),
    .appRunningCache: (
        "Close the related app before cleaning this cache.", "এই cache পরিষ্কারের আগে সংশ্লিষ্ট অ্যাপ বন্ধ করুন।",
        "أغلق التطبيق المرتبط قبل تنظيف هذه الذاكرة المؤقتة."
    ),
    .protectedCache: (
        "Protected or unsupported cache location.", "সুরক্ষিত বা অসমর্থিত cache অবস্থান।", "موقع مؤقت محمي أو غير مدعوم."
    ),
    .incompleteCache: (
        "Incomplete scan. This folder cannot be cleaned.", "স্ক্যান অসম্পূর্ণ। এই ফোল্ডার পরিষ্কার করা যাবে না।",
        "الفحص غير مكتمل. لا يمكن تنظيف هذا المجلد."
    ),
    .freshScanRequired: (
        "Run a fresh scan before selecting this item.", "এই আইটেম নির্বাচনের আগে আবার স্ক্যান করুন।",
        "أعد الفحص قبل تحديد هذا العنصر."
    ),
    .modified: ("Modified", "পরিবর্তিত", "آخر تعديل"),
    .filePath: ("Path", "ফাইলের পথ", "المسار"),
    .boostReview: ("Your Smart Boost plan", "আপনার Smart Boost পরিকল্পনা", "خطة التحسين الذكي"),
    .boostIntro: (
        "Choose apps you no longer need and cache folders you have reviewed. Every action is optional; high usage alone does not mean an app is unnecessary.",
        "অপ্রয়োজনীয় অ্যাপ ও যাচাই করা cache ফোল্ডার বেছে নিন। প্রতিটি কাজ ঐচ্ছিক; বেশি ব্যবহার মানেই অ্যাপ অপ্রয়োজনীয় নয়।",
        "اختر التطبيقات التي لم تعد تحتاجها ومجلدات الذاكرة المؤقتة التي راجعتها. كل إجراء اختياري؛ الاستهلاك المرتفع وحده لا يعني أن التطبيق غير ضروري."
    ),
    .boostApplications: ("Apps to quit gracefully", "স্বাভাবিকভাবে বন্ধ করার অ্যাপ", "تطبيقات لإنهائها طبيعياً"),
    .boostCaches: ("Cache folders to move to Trash", "Trash-এ পাঠানোর cache ফোল্ডার", "مجلدات مؤقتة لنقلها إلى السلة"),
    .boostAdvice: ("Current findings", "বর্তমান পরামর্শ", "النتائج الحالية"),
    .noEligibleApps: (
        "No eligible background applications.", "উপযুক্ত background অ্যাপ নেই।", "لا توجد تطبيقات خلفية مؤهلة."
    ),
    .noEligibleCaches: (
        "No cache folders available for cleanup.", "পরিষ্কারের উপযুক্ত cache ফোল্ডার নেই।", "لا توجد مجلدات مؤقتة متاحة للتنظيف."
    ),
    .executePlan: ("Run selected actions…", "নির্বাচিত কাজ চালান…", "نفّذ الإجراءات المحددة…"),
    .verifyBefore: ("Measuring the starting state…", "শুরুর অবস্থা মাপা হচ্ছে…", "جارٍ قياس الحالة الأولية…"),
    .applyingActions: ("Applying approved actions…", "অনুমোদিত কাজ চলছে…", "جارٍ تنفيذ الإجراءات الموافق عليها…"),
    .verifyAfter: ("Measuring the observed result…", "পরবর্তী অবস্থা মাপা হচ্ছে…", "جارٍ قياس النتيجة الملحوظة…"),
    .progressCount: ("%d of %d actions", "%d / %dটি কাজ", "%d من %d إجراءات"),
    .boostResults: ("Smart Boost results", "Smart Boost-এর ফল", "نتائج التحسين الذكي"),
    .observedResults: ("Observed results", "পর্যবেক্ষিত ফল", "النتائج الملحوظة"),
    .before: ("Before", "আগে", "قبل"), .after: ("After", "পরে", "بعد"),
    .observedChange: ("Observed change", "পর্যবেক্ষিত পরিবর্তন", "التغير الملحوظ"),
    .availableMemory: ("Estimated available memory", "আনুমানিক খালি মেমরি", "الذاكرة المتاحة المقدرة"),
    .availableDisk: ("Available storage", "খালি স্টোরেজ", "مساحة التخزين المتاحة"),
    .applicationCount: ("Running apps", "চলমান অ্যাপ", "التطبيقات العاملة"),
    .cpuWindow: (
        "CPU interval average", "CPU-এর ব্যবধানের গড়", "متوسط CPU خلال الفترة"
    ),
    .noMeasurement: ("Measurement unavailable", "পরিমাপ পাওয়া যায়নি", "القياس غير متاح"),
    .resultsWarning: (
        "These are observations, not a speed guarantee. Other activity can affect CPU, memory, and APFS capacity. Data in Trash still occupies storage.",
        "এগুলো পর্যবেক্ষণ, গতি বৃদ্ধির নিশ্চয়তা নয়। অন্য কাজ CPU, memory ও APFS capacity বদলাতে পারে। Trash-এর ডেটা এখনও জায়গা নেয়।",
        "هذه ملاحظات وليست ضماناً للسرعة. قد يؤثر نشاط آخر في CPU والذاكرة وسعة APFS. لا تزال بيانات السلة تشغل مساحة."
    ),
    .cancelExplanation: (
        "Cancellation stops future actions. Completed moves stay in Trash and sent quit requests cannot be withdrawn.",
        "বাতিল করলে বাকি কাজ থামে। সরানো ফাইল Trash-এ থাকে; পাঠানো quit অনুরোধ ফেরানো যায় না।",
        "يوقف الإلغاء الإجراءات التالية. تبقى الملفات المنقولة في السلة ولا يمكن سحب طلبات الإنهاء المرسلة."
    ),
    .done: ("Done", "সম্পন্ন", "تم"), .retry: ("Try again", "আবার চেষ্টা", "حاول مجدداً"),
    .viewStorage: ("Open Storage", "স্টোরেজ খুলুন", "افتح التخزين"),
    .openTrash: ("Open Trash", "Trash খুলুন", "افتح سلة المهملات"),
    .successMoved: ("Moved to Trash", "Trash-এ পাঠানো হয়েছে", "نُقل إلى السلة"),
    .successQuit: ("Gracefully stopped", "স্বাভাবিকভাবে বন্ধ হয়েছে", "توقفت بشكل طبيعي"),
    .stillWaiting: (
        "Still running; may be waiting to save work", "এখনও চলছে; কাজ সংরক্ষণের অপেক্ষা হতে পারে", "لا يزال يعمل؛ قد ينتظر حفظ العمل"
    ),
    .requestRejected: ("Quit request was not accepted", "বন্ধের অনুরোধ গ্রহণ হয়নি", "لم يُقبل طلب الإنهاء"),
    .identityChanged: (
        "Identity unavailable, changed, or protected", "পরিচয় পাওয়া যায়নি, বদলেছে বা সুরক্ষিত", "الهوية غير متاحة أو تغيرت أو محمية"
    ),
    .actionCancelled: ("Not run · cancelled", "চালানো হয়নি · বাতিল", "لم يُنفذ · أُلغي"),
    .actionFailed: ("Could not complete", "সম্পন্ন করা যায়নি", "تعذر الإكمال"),
    .details: ("Details", "বিস্তারিত", "التفاصيل"),
    .snoozeHour: ("Snooze for 1 hour", "১ ঘণ্টা স্থগিত", "تأجيل لمدة ساعة"),
    .restoreRecommendations: ("Restore snoozed recommendations", "স্থগিত পরামর্শ ফিরিয়ে আনুন", "استعد التوصيات المؤجلة"),
    .cacheCleanupHistory: ("Cache cleanup", "Cache পরিষ্কার", "تنظيف الذاكرة المؤقتة"),
    .fileScanHistory: ("File analysis", "ফাইল বিশ্লেষণ", "تحليل الملفات"),
    .fileCleanupHistory: ("Reviewed files moved to Trash", "যাচাই করা ফাইল Trash-এ সরানো", "نقل ملفات مراجعة إلى السلة"),
    .boostHistory: ("Smart Boost", "Smart Boost", "التحسين الذكي"),
    .failedStatus: ("Failed", "ব্যর্থ", "فشل"), .partialStatus: ("Partially completed", "আংশিক সম্পন্ন", "اكتمل جزئياً"),
    .cancelledStatus: ("Cancelled", "বাতিল", "أُلغي"),
    .itemNoLongerExists: (
        "The item no longer exists. Scan again.", "আইটেমটি আর নেই। আবার স্ক্যান করুন।", "لم يعد العنصر موجوداً. أعد الفحص."
    ),
    .finderUnavailable: (
        "Finder could not open this location.", "Finder এই অবস্থান খুলতে পারেনি।", "تعذر على Finder فتح هذا الموقع."
    ),
    .operationFailed: ("Operation could not complete", "কাজ সম্পন্ন করা যায়নি", "تعذر إكمال العملية"),
    .scanCancelledPartial: (
        "Scan cancelled. Previous results have been kept.", "স্ক্যান বাতিল। আগের ফল রাখা হয়েছে।",
        "أُلغي الفحص. تم الاحتفاظ بالنتائج السابقة."
    ),
    .cacheRebuildWarning: (
        "Caches may contain useful state. Apps can redownload or rebuild them, which may take time. Active app caches and protected locations are excluded.",
        "Cache-এ দরকারি অবস্থা থাকতে পারে। অ্যাপকে আবার download বা rebuild করতে সময় লাগতে পারে। চলমান অ্যাপের cache ও সুরক্ষিত অবস্থান বাদ যায়।",
        "قد تحتوي الذاكرة المؤقتة على حالة مفيدة. قد يستغرق تنزيلها أو بناؤها مجدداً وقتاً. تُستبعد ذاكرة التطبيقات النشطة والمواقع المحمية."
    ),
    .fileCleanupWarning: (
        "These may be personal files. Check names, paths, and content before choosing copies to remove.",
        "এগুলো ব্যক্তিগত ফাইল হতে পারে। সরানোর আগে নাম, পথ ও ডেটা যাচাই করুন।",
        "قد تكون هذه ملفات شخصية. تحقق من الأسماء والمسارات والمحتوى قبل اختيار النسخ لإزالتها."
    ),
    .nothingSelected: ("Select items to build a plan.", "পরিকল্পনা করতে আইটেম বেছে নিন।", "حدد عناصر لإنشاء خطة."),
    .reviewSafety: (
        "Save your work before quitting apps. No action runs until you approve this plan.",
        "অ্যাপ বন্ধের আগে কাজ সংরক্ষণ করুন। এই পরিকল্পনা অনুমোদনের আগে কোনো কাজ হবে না।",
        "احفظ عملك قبل إنهاء التطبيقات. لن يُنفذ إجراء حتى توافق على الخطة."
    ),
    .cpuPerCore: ("CPU · 100% = one core", "CPU · ১০০% = একটি core", "CPU · 100% = نواة واحدة"),
    .processResources: (
        "Review live application CPU and memory. Choose only apps you no longer need.",
        "অ্যাপের CPU ও memory দেখুন। শুধু অপ্রয়োজনীয় অ্যাপ বেছে নিন।", "راجع CPU والذاكرة للتطبيقات. اختر فقط ما لم تعد تحتاجه."
    ),
    .historyOperationCount: ("%d items completed", "%dটি আইটেম সম্পন্ন", "اكتمل %d عنصراً"),
    .swapNowAvailable: (
        "Swap usage is read from macOS when permitted.", "অনুমতি থাকলে macOS থেকে swap usage পড়া হয়।",
        "تُقرأ مساحة التبديل من macOS عند السماح."
    ),
    .refreshVersions: ("Check versions", "সংস্করণ যাচাই", "تحقق من الإصدارات"),
    .developerChecking: ("Checking installed tools…", "ইনস্টল করা টুল যাচাই হচ্ছে…", "جارٍ فحص الأدوات المثبتة…"),
    .developerVersions: ("Installed tool versions", "ইনস্টল করা টুলের সংস্করণ", "إصدارات الأدوات المثبتة"),
    .developerTimeout: ("The tool did not respond in time.", "সময়ের মধ্যে টুল উত্তর দেয়নি।", "لم تستجب الأداة في الوقت المحدد."),
    .developerUnavailable: ("Unavailable or not running", "পাওয়া যায়নি বা চলছে না", "غير متاح أو لا يعمل"),
    .developerReadOnly: (
        "Checks run locally with fixed arguments. Packages, projects, containers, and volumes are not changed.",
        "নির্দিষ্ট argument দিয়ে স্থানীয়ভাবে যাচাই হয়। Package, project, container বা volume বদলায় না।",
        "تُجرى الفحوص محلياً بمعاملات ثابتة. لا تتغير الحزم أو المشاريع أو الحاويات أو وحدات التخزين."
    ),
]
