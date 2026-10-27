<!-- Avtomatik nusxa: scripts/sync-ios-hooks.sh. Qo'lda tahrirlamang. -->
<!-- Manba: Telegram-iOS/submodules/Fenixuz/HOOKS.md (5a4e334c74 2026-10-15) -->

# 📋 Novagram features va hooklar (2026-10-10)

> 1–44: Settings → Novagram Settings (ilovadagi tartibda). 45–85: Settings'dan tashqaridagi features.
> Hooks: Telegram-owned fayllardagi barcha Fenixuz o'zgarishlari, feature bo'yicha. Har bir hookning kodi va anchor'i iOS repodagi `submodules/Fenixuz/HOOKS.md` ning 📌 bo'limlarida.

## 1. Novagram Settings

> Settings → Novagram Settings. Tartib ilovadagi bilan bir xil.

### Novagram haqida

1. **Novagram haqida**: har bir imkoniyat qanday yoqiladi, qanday ishlaydi va qanday o'chiriladi.

### Accountlar

2. **Barcha accountlar**: barcha accountlar ro'yxati (joriy, faol, uyquda). Shu yerdan "Faollashtirish (Uyqusiz)" yoki "Uyquga qo'yish".

### Interfeys

3. **Jildlarni yashirish**: chatlar ro'yxati tepasidagi papka tablarini vaqtincha yashiradi.
4. **Hikoyalar paneli**: chatlar ro'yxati tepasidagi stories panelini ko'rsatadi yoki yashiradi.
5. **Mutual kontakt belgisi**: sizni ham kontaktiga saqlaganlar yonida 🤝 belgisi chiqadi.
6. **Cheksiz pin**: 1000 tagacha chatni pin qilish mumkin. Limitdan ortiq pinlar faqat shu iPhone'da saqlanadi.

### Chat

7. **O'chirilgan xabarlar**: boshqalar o'chirgan xabarlar chatda qoladi, 🗑 belgisi va o'chirilgan vaqti bilan.
8. **Tahrirlangan xabar tarixi**: xabarning barcha oldingi versiyalari (matn va media) saqlanadi. Ko'rish: xabarni long-press → "Tahrir tarixi".
9. **Birinchi xabarga o'tish**: profil menyusiga "View First Message" qo'shiladi va chatning eng birinchi xabariga o'tadi.
10. **Ghost rejimi tugmasi**: chatlar ro'yxati tepasiga Ghost tugmasi qo'shiladi. Ghost yoqilganda "ko'rildi", "yozyapti" va "onlayn" signallari yuborilmaydi.
11. **Kamerani tanlash**: video-xabar tugmasini long-press qilib old yoki orqa kamerani tanlash.
12. **Galereyadan dumaloq video**: galereyadagi videoni dumaloq video-xabar qilib yuborish (1 daqiqagacha).
13. **Imzosiz forward**: xabar menyusiga "Imzosiz forward qilish" qo'shiladi. Xabar yuboruvchi nomisiz forward qilinadi.

### Xabarlar

14. **Yozuv uslubi**: har bir chiquvchi xabarga bitta format qo'llanadi (Bold, Italic, Monospace, Strikethrough, Underline yoki Spoiler).
15. **Avto-matn qo'shimchasi**: har bir xabar oxiriga o'zingiz yozgan matn (imzo, hashtag) avtomatik qo'shiladi.
16. **Avto-tarjima**: chiquvchi xabarlar yuborishdan oldin tanlangan tilga tarjima qilinadi.
17. **Tarjima tugmasi**: har bir matnli xabar menyusida "Translate" chiqadi.
18. **Tarjima tili**: "Translate" uchun maqsad tilni tanlash va til paketlarini yuklab olish.
19. **Yuborishda tarjima so'rovi**: Send bosilganda tarjimani yoki aslini yuborish so'raladi.
20. **Avtomatik sticker**: har bir matnli xabardan keyin oxirgi yuborilgan sticker ham yuboriladi.
21. **Yurakcha effekti**: yuborilgan xabarlarga ❤️ animatsion effekt avtomatik qo'shiladi.

### Ovoz → Matn

22. **Ovozni matnga o'girish**: mikrofon yonida STT tugmasi chiqadi. Aytilgan gap matnga aylanib input'ga yoziladi.
23. **Tanish tili**: STT tilini tanlash. O'zbek tili offline Vosk modeli orqali taniladi.
24. **Ovozli xabarlarni tarjima qilish**: ovozdan olingan matn avtomatik tarjima qilinadi.

### Himoya

25. **Xorijiy raqamlarni bloklash**: boshqa davlat raqamlaridan kelgan chat, xabar va bildirishnomalarni yashiradi.
26. **Chat qulfi**: avval asosiy pinkod o'rnatiladi. Keyin chatni long-press → "Qulf o'rnatish" (PIN yoki parol, Face ID/Touch ID ham ishlaydi).
27. **Avto-yuklashni o'chirish**: mobil tarmoq va Wi-Fi'da barcha media avto-yuklashni o'chiradi.
28. **Yuborishdan oldin so'rash**: ovozli xabar, sticker yoki sovg'a yuborishdan oldin tasdiq so'raladi.
29. **NovagramProxy'ni yoqish**: Telegram bloklangan hududda avtomatik SOCKS5 proxy orqali ulanadi.

### Ko'rinish

30. **Yorqin temada brand rangi**: yorqin (oq) temada Novagram ko'k rangi accent bo'ladi.

### Chat qulfi

31. **Yashirin chatlar**: tanlangan chatlar alohida kod-parol ortiga yashiriladi va ovozsiz qilinadi. Ochish uchun "Chats" sarlavhasi long-press qilinadi.
32. **Face ID bilan ochish**: yashirin chatlarni Face ID yoki Touch ID bilan ochish.

### Xabar eslatmasi

33. **O'qilmagan xabar eslatmasi**: xabar belgilangan vaqtda o'qilmasa lokal eslatma keladi.
34. **Eslatma vaqti**: 1 dan 60 daqiqagacha.
35. **Eslatma ovozi**: 12 ta ohangdan biri, standart ovoz yoki "Yo'q".

### Imkoniyatlar

36. **Tavsiya etilgan papkalar**: bir bosishda Shaxsiy, O'qilmagan, Kanallar va Botlar papkalari yaratiladi.
37. **Admin papkalar**: siz ega (👑) yoki admin (🔑) bo'lgan guruh va kanallar 4 ta avto-papkaga ajratiladi.
38. **Papka ko'rinishi**: papka tablari uchun Ikonkalar, Matn yoki Avtomatik ko'rinish.
39. **Kanal tarixi tugmasi**: siz admin bo'lgan kanal menyusiga "So'nggi amallar" qo'shiladi.
40. **Avto-qabul qilish**: guruh va kanalga qo'shilish so'rovlari avtomatik qabul qilinadi.
41. **Novagram Settings havolasini ulashish**: `tg://settings/novagrampro` havolasini nusxalash yoki ulashish. Istalgan qatorni long-press qilsangiz, aynan o'sha qatorga olib boradigan havola chiqadi.
42. **Hikoyalarni saqlash va sifat**: boshqalarning hikoyalarini saqlash va video hikoyalarni HD ko'rish (Premium'siz).
43. **Butun chatni tarjima qilish**: butun chatni bir yo'la tarjima qilish (Premium'siz).

### Reklama

> Yashirin bo'lim. Ochish uchun sahifani 10 marta tez bosing.

44. **Reklamani ko'rsatish**: kanal va banner reklamalarini yoqadi yoki o'chiradi.

---

## 2. Settings'dan tashqaridagi features

### Login

45. **QR kod orqali kirish**: telefon raqam ekranida QR kod bilan kirish tugmasi.
46. **Bot token bilan kirish**: telefon raqami o'rniga bot token bilan kirish. Bot sessiyasida faqat Chats va Settings tablari bor.
47. **Login ekranidagi NovagramProxy**: bloklangan hududda login'dan oldin proxy'ni yoqadigan tugma.
48. **2FA "Orqaga" tugmasi**: 2FA parol ekranidan orqaga qaytish mumkin, user ekranda qamalib qolmaydi.

### Chat va xabarlar

49. **Tahrirlab yuborish**: forward qilinayotgan post tahrirlanadi va "Forwarded from" hamda "edited" belgisisiz yangi xabar bo'lib ketadi.
50. **Maxfiy ko'rish**: chatlar ro'yxatida long-press. Chat "o'qildi" signali yubormasdan ochiladi.
51. **Chat ID'ni nusxalash**: chatlar ro'yxatida long-press qilib chat ID'sini nusxalash.
52. **Profildagi ID qatori**: user, guruh va kanal profilida ID ko'rinadi (guruh va kanalda `-100…` formatida). Bosilsa nusxalanadi.
53. **Novagram Info**: profil "…" menyusida ID, turi, username va Premium/Scam/Fake belgilari chiqadi.
54. **Telefon raqamda "Qayta urinish"**: tarmoq xatosi "Telegram'da yo'q" deb ko'rsatilmaydi, o'rniga "Qayta urinish" chiqadi.

### Chat ro'yxati va papkalar

55. **Papka ikonkasini tanlash**: papka tahrirlash ekranida emoji ikonka tanlanadi (Premium'siz).
56. **Cheksiz papka va teglar**: papka limiti oshirilgan, "Show Folder Tags" Premium'siz ishlaydi.
57. **Header tugmalarini yig'ish**: Stories, Ghost va Proxy tugmalari 2 tadan ko'p bo'lsa bitta chevron ortiga yig'iladi.

### Multi-account

58. **999 tagacha account**: account limiti 999, Premium shart emas.
59. **Uyquchi accountlar**: joriy va 5 tagacha faol account doim ulangan turadi. Qolganlari uxlaydi, lekin push keladi va 1–2 soniyada uyg'onadi.
60. **Tab bar'dan account almashtirish**: Settings tabini long-press qilganda barcha accountlar avatar va username bilan chiqadi.
61. **Bildirishnomalarni tozalash**: o'qilgan xabar bildirishnomasi barcha faol accountlarda o'chadi.

### Qo'ng'iroq va bildirishnomalar

62. **Kiruvchi qo'ng'iroq fallback**: ilova yopiq bo'lsa ham qo'ng'iroq ringtone va vibratsiya bilan jiringlaydi.
63. **Uxlayotgan accountga qo'ng'iroq**: uxlayotgan accountga qo'ng'iroq kelsa account uyg'otiladi.
64. **Bildirishnomada yuboruvchi rasmi**: push'da yuboruvchining avatari ko'rinadi (Communication Notifications).

### Ilova va Settings

65. **Novagram Settings qatori**: Settings'dagi oltin rangli qator. Barcha Novagram sozlamalari shu yerda.
66. **Novagram Bots**: kategoriyalarga bo'lingan foydali botlar katalogi.
67. **Analytics**: Novagram foydalanuvchilari (qurilmalar) va faol accountlar soni.
68. **Settings havolalari**: `tg://settings/novagrampro/<feature>` havolasi kerakli qatorni ochib, uni belgilab ko'rsatadi.
69. **Ilova ikonkalari**: 7 ta Nova ikonka (Ko'k, Feruza, Binafsha, Pushti, To'q sariq, Qora, Qizil).
70. **Imkoniyatlar ekrani (Tips)**: birinchi ishga tushishda asosiy imkoniyatlar bir marta ko'rsatiladi.
71. **Yangilanish tekshiruvi**: App Store'da yangi versiya bo'lsa "Yangilanish mavjud" alerti chiqadi.
72. **Haptic**: header tugmalari, story kamera va STT tugmasi bosilganda yengil vibratsiya beradi.

### Brand va til

73. **Novagram brendi**: ilova nomi, ikonka, ko'k rang (`#0A9BF5`) va intro ekrani Novagram'niki.
74. **Server matnlarida Novagram**: server'dan keladigan tarjimalardagi "Telegram" so'zi "Novagram"ga almashtiriladi.
75. **Tizimdagi Novagram nomi**: CallKit, Share, Widget, Siri, Photos albomi, kontakt label'i va ruxsat so'rovlarida ham "Novagram" yoziladi.
76. **Xitoy tili**: Settings → Language'da Simplified va Traditional Chinese bor. Novagram ekranlari ham xitoychaga tarjima qilingan.
77. **4 tilli Novagram matnlari**: barcha Novagram matnlari en, uz, ru va zh tillarida. Boshqa tillarda English chiqadi.

### Reklama va statistika

78. **Kanal reklamasi**: kanallardagi sponsored joyda Novagram reklamasi ko'rsatiladi.
79. **Banner reklama**: chatlar ro'yxati tepasida Novagram banneri chiqadi. Yopilgan banner qayta chiqmaydi.
80. **Qidiruv reklamasi**: global qidiruvda so'rovga mos promoted kanal eng tepada turadi.
81. **Anonim statistika**: anonim device ID bilan o'rnatishlar va faol accountlar soni yuboriladi (ATT shart emas).

### Apple talablari

82. **IAP blok (3.1.1)**: ilova ichida Premium yoki Stars sotib olib bo'lmaydi (StoreKit olib tashlangan). Alert @PremiumBot'ga yo'naltiradi.
83. **To'lov bo'limi faqat ko'rish uchun**: Premium, Stars, TON, Business va Gift ekranlari ko'rinadi, lekin xarid tugmalari bloklangan.
84. **Kontaktlar roziligi (5.1.2)**: iOS Contacts ruxsatidan oldin kontaktlar serverga yuklanishiga rozilik so'raladi.
85. **Demo login**: Apple Review demo raqami kiritilsa SMS kod avtomatik to'ldiriladi.

---

## 3. Hooks

> Telegram-owned fayllardagi Fenixuz o'zgarishlari, feature bo'yicha. Qavs ichida modul nomi.

### Accountlar

1. `AccountUtils.swift` (AccountUtils): account limiti 999.
2. `DeleteAccountOptionsController.swift`, `LogoutOptionsController.swift` (SettingsUI): hardcoded 3/4 o'rniga umumiy limit ishlatiladi.
3. `AccountContext.swift` (AccountContext): pinned accountlar uchun 4 ta protokol a'zosi.
4. `SharedAccountContext.swift` (TelegramUI): 5 tagacha live account (LRU), pinned accountlar, ism/username/avatar keshi. Xotira kam bo'lsa kesh tozalanadi.
5. `SharedWakeupManager.swift` (TelegramUI): pinned accountlar doim ulangan turadi.
6. `PeerInfoSettingsItems.swift` (PeerInfoScreen): Settings'da "Barcha accountlar" qatori.
7. `PeerInfoScreen.swift` (PeerInfoScreen): Settings tabini long-press qilganda barcha accountlar chiqadi.
8. `PeerInfoScreenSettingsActions.swift` (PeerInfoScreen): "Barcha accountlar" ekranini ochadi, Add Account limiti.
9. `FenixAccountSwitchContextItem.swift` (PeerInfoScreen, yangi fayl): account qatori (avatar, ism, @username).

### Interfeys

10. `ChatListController.swift` (ChatListUI): **Jildlarni yashirish**: faqat "All Chats" tabi qoladi.
11. `ChatListControllerNode.swift` (ChatListUI): **Hikoyalar paneli**: stories paneli yashiriladi.
12. `ContactsPeerItem.swift` (ContactsPeerItem): **Mutual kontakt belgisi**: kontakt nomi yonida 🤝 chiqadi.
13. `TogglePeerChatPinned.swift` (TelegramCore): **Cheksiz pin**: pin limiti 1000.
14. `FenixuzLocalPins.swift` (TelegramCore, yangi fayl): **Cheksiz pin**: server limitidan ortiq pinlar qurilmada saqlanadi.
15. `Holes.swift`, `ResetState.swift`, `ManagedSynchronizePinnedChatsOperations.swift` (TelegramCore): **Cheksiz pin**: server bilan sync'da lokal pinlar qaytadan qo'shiladi.
16. `TelegramEnginePeers.swift` (TelegramCore): **Cheksiz pin**: o'chirilganda ortiqcha pinlar olib tashlanadi.

### O'chirilgan xabarlar

17. `DeletedMessageAttribute.swift` (TelegramCore, yangi fayl): o'chirilgan xabar belgisi va o'chirilgan vaqti.
18. `FenixuzShowDeletedMessages.swift` (TelegramCore, yangi fayl): toggle App Group orqali NotificationService'ga ham ko'rinadi.
19. `AccountManager.swift` (TelegramCore): `DeletedMessageAttribute` registratsiyasi.
20. `AccountStateManagementUtils.swift` (TelegramCore): o'chirish kelganda xabar o'chirilmaydi, unga belgi qo'yiladi.
21. `SyncCore_StandaloneAccountTransaction.swift` (TelegramCore): re-sync'da 🗑 belgisi saqlanadi.
22. `HistoryViewStateValidation.swift` (TelegramCore): tarix tekshiruvida saqlangan xabar o'chirilmaydi.
23. `NotificationService.swift` (NotificationService): ilova fonda bo'lsa ham o'chirilgan xabar saqlanadi.
24. `AppDelegate.swift` (TelegramUI): har launch'da toggle App Group'ga ko'chiriladi.
25. `ChatHistoryEntriesForView.swift` (TelegramUI): toggle o'chiq bo'lsa o'chirilgan xabarlar ko'rsatilmaydi.
26. `ChatHistoryListNode.swift` (TelegramUI): toggle o'zgarsa ochiq chat darhol yangilanadi.
27. `StringForMessageTimestampStatus.swift` (TelegramUI): xabar ostida "🗑 O'chirilgan · vaqt" yoziladi.

### Tahrirlangan xabar tarixi

28. `SyncCore_EditedMessageHistoryAttribute.swift` (TelegramCore, yangi fayl): xabarning eski versiyalari (matn va media).
29. `FenixuzEditHistoryCapture.swift` (TelegramCore, yangi fayl): tarixni yozadigan umumiy helper.
30. `AccountManager.swift` (TelegramCore): `EditedMessageHistoryAttribute` registratsiyasi.
31. `AccountStateManagementUtils.swift` (TelegramCore): tahrir kelganda tarix yoziladi.
32. `RequestEditMessage.swift` (TelegramCore): o'zingizning birinchi tahriringiz ham saqlanadi.
33. `SyncCore_StandaloneAccountTransaction.swift` (TelegramCore): guruh va kanal re-sync'da tarix yo'qolmaydi.
34. `ChatInterfaceStateContextMenus.swift` (TelegramUI): xabar menyusida "Tahrir tarixi" (toggle bilan).

### Birinchi xabarga o'tish

35. `ChatController.swift` (AccountContext): `navigateToFirstMessage()` protokol a'zosi.
36. `ChatController.swift` (TelegramUI): `navigateToFirstMessage()` va chatdagi avatar menyularida "View First Message".
37. `PeerInfoScreenPerformButtonAction.swift` (PeerInfoScreen): user, guruh va kanal profilining "…" menyusida "View First Message".

### Ghost rejimi

38. `FenixuzGhostMode.swift` (TelegramCore, yangi fayl): `isFenixuzGhostModeActive`, Ghost uchun umumiy tekshiruv.
39. `FenixuzGhostReadOnSend.swift` (TelegramCore, yangi fayl): javob yuborilganda chat o'qilgan bo'ladi.
40. `EnqueueMessage.swift` (TelegramCore): xabar yuborilganda chat o'qilgan qilinadi.
41. `ApplyMaxReadIndexInteractively.swift` (TelegramCore): forum, topic va saved chatlar uchun o'qildi/o'qilmadi belgisi yuborilmaydi.
42. `SynchronizePeerReadState.swift` (TelegramCore): read receipt yuborilmaydi.
43. `AccountContext.swift` (TelegramUI): `applyMaxReadIndex` ishlamaydi.
44. `MarkAllChatsAsRead.swift` (TelegramCore): "Hammasini o'qilgan qilish" serverga yuborilmaydi.
45. `ManagedAccountPresence.swift` (TelegramCore): "onlayn" holati yuborilmaydi.
46. `ManagedLocalInputActivities.swift` (TelegramCore): "yozyapti" yuborilmaydi.
47. `ManagedSynchronizeViewStoriesOperations.swift` (TelegramCore): story ko'rilgani yuborilmaydi.
48. `Stories.swift` (TelegramCore): story ko'rishlar soni oshmaydi.
49. `AccountViewTracker.swift` (TelegramCore): kanal post ko'rishlar soni oshmaydi, reaksiyalar "ko'rildi" bo'lmaydi.
50. `ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift` (TelegramCore): reaksiya va mention o'qilgani yuborilmaydi.
51. `ManagedConsumePersonalMessagesActions.swift` (TelegramCore): reaksiya va poll uchun `readMessageContents` yuborilmaydi.
52. `ManagedSynchronizeConsumeMessageContentsOperations.swift` (TelegramCore): ovozli va video xabar "eshitildi" deb yuborilmaydi.
53. `MarkMessageContentAsConsumedInteractively.swift` (TelegramCore): media "ochildi" deb yuborilmaydi.
54. `PeerMessagesMediaPlaylist.swift` (TelegramUI): ovozli xabar tinglansa ham "eshitildi" bo'lmaydi.
55. `SecretMediaPreviewController.swift` (GalleryUI): yo'qoladigan media ochilgani yuborilmaydi.
56. `StandaloneSendMessage.swift`, `PendingMessageManager.swift` (TelegramCore): screenshot bildirishnomasi yuborilmaydi.
57. `AdMessages.swift` (TelegramCore): reklama "ko'rildi" va click yuborilmaydi.
58. `ChatListController.swift` (ChatListUI): chatlar tepasida Ghost tugmasi (yoqiq/o'chiq ikonka).
59. `NavigationButtonComponent.swift` (TelegramUI): Ghost ikonkasi uchun yangi `Content` turlari, katta ikonka kichraytiriladi.
60. `FenixGhostActive/Inactive/Icon.imageset` (TelegramUI, yangi asset): Ghost ikonkalari.

### Chat

61. `ChatTextInputPanelNode.swift` (TelegramUI): **Kamerani tanlash**: long-press'da old/orqa kamera menyusi chiqadi (lokalizatsiya qilingan, klaviatura bilan to'qnashuv tuzatilgan, default OFF).
62. `ChatTextInputPanelNode.swift` (TelegramUI): **Galereyadan dumaloq video**: kamera menyusida "Galereya" bandi.
63. `ChatInterfaceStateContextMenus.swift` (TelegramUI): **Imzosiz forward**: xabar menyusida "Imzosiz forward qilish".
64. `ChatControllerForwardMessages.swift` (TelegramUI): **Imzosiz forward**: bir martalik "nomsiz" bayrog'i o'qiladi va tozalanadi.

### Xabarlar

65. `ChatControllerNode.swift` (TelegramUI): **Yozuv uslubi** va **Avto-matn**: yuborishda xabarga format va matn qo'shiladi.
66. `ChatController.swift` (TelegramUI): **Yozuv uslubi**: ikkinchi yuborish yo'lida ham format qo'llanadi.
67. `ChatControllerNode.swift` (TelegramUI): **Avto-tarjima** (#31) va **Yuborishda tarjima so'rovi** (#37). Rich xabarda ishlamaydi.
68. `ChatInterfaceStateContextMenus.swift` (TelegramUI): **Tarjima tugmasi**: "Translate" doim chiqadi.
69. `ChatController.swift` (TelegramUI): **Tarjima tili**: maqsad til Novagram sozlamasidan olinadi.
70. `ChatController.swift` (TelegramUI): **Avtomatik sticker** (#30): oxirgi yuborilgan sticker saqlanadi.
71. `ChatControllerNode.swift` (TelegramUI): **Avtomatik sticker** (#30) matndan keyin yuboriladi. **Yurakcha effekti** (#34) qo'shiladi.

### Ovoz → Matn

72. `ChatTextInputPanelNode.swift` (TelegramUI): STT tugmasi (chapda) va haptic. Long-press'da til va ovozli tarjima sozlamalari ochiladi. Default OFF.

### Himoya

73. `ChatListNodeEntries.swift` (ChatListUI): **Xorijiy raqamlar**: chatlar ro'yxatida ko'rinmaydi.
74. `ChatHistoryEntriesForView.swift` (TelegramUI): **Xorijiy raqamlar**: ularning xabarlari yashiriladi.
75. `NotificationService.swift` (NotificationService): **Xorijiy raqamlar**: ulardan bildirishnoma chiqmaydi.
76. `AccountContext.swift` (TelegramUI): **Xorijiy raqamlar**: davlat kodini solishtirish uchun o'z raqamingiz saqlanadi.
77. `ChatContextMenus.swift` (ChatListUI): **Chat qulfi**: "Qulf o'rnatish/olib tashlash" bandi (faqat asosiy pinkod bo'lsa).
78. `ChatListController.swift` (ChatListUI): **Chat qulfi**: qulflangan chatning preview'i ko'rsatilmaydi.
79. `NavigateToChatController.swift` (TelegramUI): **Chat qulfi**: chatga kirishda PIN/Face ID so'raladi. "Pinkodni unutdingizmi?" asosiy pinkod orqali ishlaydi.
80. `ChatControllerMediaRecording.swift` (TelegramUI): **Yuborishdan oldin so'rash** (#38): ovozli xabar tasdig'i.
81. `ChatController.swift` (TelegramUI): **Yuborishdan oldin so'rash** (#38): sticker tasdig'i.
82. `ChatInterfaceStateContextMenus.swift` (TelegramUI): **Yuborishdan oldin so'rash** (#38): sovg'a tasdig'i.
83. `AppDelegate.swift` (TelegramUI): **NovagramProxy**: launch'da proxy tekshiriladi va tiklanadi.
84. `AuthorizationSequencePhoneEntryController.swift` (AuthorizationUI): **NovagramProxy**: login ekranida proxy tugmasi.

### Yashirin chatlar

85. `ChatListController.swift` (ChatListUI): ochish (sarlavhani long-press yoki 10 tap), Hide/Unhide, story bar filtri. Papka tablari va compose tugmasi yashiriladi, Face ID default yoqiladi.
86. `ChatListContainerItemNode.swift`, `ChatListNode.swift` (ChatListUI): yashirin chatlar ro'yxati rejimi.
87. `ChatListNodeEntries.swift` (ChatListUI): yashirin chatlar asosiy ro'yxatdan olib tashlanadi. Yashirin ro'yxatda Archive yo'q.
88. `ChatListEmptyNode.swift` (ChatListUI): bo'sh holatda o'rdak sticker.
89. `ChatContextMenus.swift` (ChatListUI): "Unhide" bandi. Mute default holatga qaytadi.
90. `ContactsController.swift`, `ContactsControllerNode.swift`, `ContactListNode.swift`, `ContactContextMenus.swift` (ContactListUI): kontaktlarda yashirish va ko'rsatish. "Contacts" sarlavhasidan ham ochiladi.
91. `CallListNodeEntries.swift`, `CallListControllerNode.swift` (CallListUI): yashirin chatlarning qo'ng'iroqlari ko'rinmaydi.
92. `Toolbar.swift`, `ToolbarNode.swift` (Display), `TabBarContollerNode.swift` (TabBarUI): toolbar'da qo'shimcha "Yashirish" tugmasi.
93. `AccountContext.swift` (AccountContext), `SharedAccountContext.swift` (TelegramUI): yashirin ro'yxat ekrani factory'si.

### Xabar eslatmasi

94. `ApplicationContext.swift` (TelegramUI): eslatma menejeri ishga tushadi.

### Imkoniyatlar

95. `ApplicationContext.swift` (TelegramUI): **Tavsiya etilgan papkalar**: birinchi launch'da taklif qilinadi.
96. `AppDelegate.swift` (TelegramUI): **Admin papkalar** (#47): global monitor.
97. `ChatListController.swift` (ChatListUI): **Papka ko'rinishi** (#21): tab nomi tanlangan uslubda chiqadi.
98. `ChatContextMenus.swift` (ChatListUI): **Kanal tarixi tugmasi** (#32): kanal menyusida "So'nggi amallar".
99. `ChatController.swift` (TelegramUI): **Avto-qabul qilish** (#45): chat ochilganda so'rovlar qabul qilinadi.
100. `AppDelegate.swift` (TelegramUI): **Avto-qabul qilish** (#45): launch'da va har 60 soniyada tekshiriladi.
101. `OpenResolvedUrl.swift`, `OpenUrl.swift` (TelegramUI): **Settings havolalari** (#40): `tg://settings/novagrampro[/<feature>]`.
102. `StoryItemSetContainerComponent.swift` (StoryContainerScreen): **Hikoyalarni saqlash**: story yuklab olish va HD Premium'siz.
103. `StoryChatContent.swift` (StoryContainerScreen), `ChatListController.swift` (ChatListUI), `ChatHistoryListNode.swift` (TelegramUI): **Hikoyalar sifati**: HD sozlamasi Premium'siz ishlaydi.
104. `ChatTranslationPanelNode.swift` (TranslateHeaderPanelComponent): **Butun chatni tarjima**: tarjima paneli Premium'siz.
105. `ChatControllerContentData.swift`, `ChatHistoryListNode.swift` (TelegramUI): **Butun chatni tarjima**: tarjima xabarlarga qo'llanadi.
106. `LocalizationListControllerNode.swift` (SettingsUI): **Butun chatni tarjima**: Settings → Language'dagi switch ochiq.

### Reklama

107. `ChatHistoryListNode.swift` (TelegramUI): kanal reklamasi bizning backend'dan keladi. "Reklamani ko'rsatish" toggle shu yerda tekshiriladi.
108. `ChatController.swift` (TelegramUI): reklama bosilganda click hisoboti.
109. `ChatInterfaceStateContextMenus.swift` (TelegramUI): o'z reklamamizda Premium "Hide" bandi chiqmaydi.
110. `ChatListSearchListPaneNode.swift` (ChatListUI): qidiruv natijalari tepasida promoted kanal.
111. `GlobalControlPanelsContext.swift` (TelegramUI): chatlar ro'yxati tepasida banner va uni yopish.
112. `ChatListControllerNode.swift` (ChatListUI): banner click hisoboti.

### Login

113. `AuthorizationSequencePhoneEntryController.swift` (AuthorizationUI): nav-bar'da QR va bot-token ikonkalari.
114. `AuthorizationSequencePhoneEntryControllerNode.swift` (AuthorizationUI): QR overlay. Intro telefon animatsiyasi takrorlanadi.
115. `AuthorizationSequenceController.swift` (AuthorizationUI): bot-token ekranini ochadi, 2FA "Orqaga" ulangan.
116. `AuthorizationSequencePasswordEntryController.swift` (AuthorizationUI): 2FA ekranida "Orqaga" tugmasi.
117. `FenixuzBotAuthorization.swift` (TelegramCore, yangi fayl): bot token bilan avtorizatsiya.
118. `FenixuzBotSession.swift` (TelegramCore, yangi fayl): bot sessiyasi helper'lari.
119. `AccountStateManagementUtils.swift` (TelegramCore): bot sessiyada chatlar ro'yxatga chiqadi, DM unread ishlaydi.
120. `ManagedChatListHoles.swift`, `ManagedMessageHistoryHoles.swift` (TelegramCore): bot sessiyada chat va tarix yuklanishi qotib qolmaydi.
121. `ManagedPendingPeerNotificationSettings.swift` (TelegramCore): bot sessiyada mute saqlanadi.
122. `ChatListFiltering.swift` (TelegramCore): bot sessiyada papka tablari ishlaydi.
123. `TelegramRootController.swift` (TelegramUI): bot sessiyada faqat Chats va Settings tablari.
124. `PeerInfoScreenSettingsActions.swift` (PeerInfoScreen): telefonsiz bot accountdan chiqish.
125. `AppDelegate.swift` (TelegramUI): telefonsiz bot account uchun nom.

### Chat va xabarlar (Settings'dan tashqari)

126. `ChatMessageActionOptions.swift` (TelegramUI): **Tahrirlab yuborish** (#39): forward menyusidagi band.
127. `ChatContextMenus.swift` (ChatListUI): **Maxfiy ko'rish** va **Chat ID'ni nusxalash** (#24).
128. `PeerInfoProfileItems.swift` (PeerInfoScreen): **Profildagi ID qatori**, bosilsa nusxalanadi.
129. `PeerInfoScreenPerformButtonAction.swift` (PeerInfoScreen): **Novagram Info** profil "…" menyusida.
130. `ResolvePeerByName.swift`, `TelegramEnginePeers.swift` (TelegramCore): **Telefon raqam**: tarmoq xatosi alohida natija bo'lib qaytadi.
131. `ChatControllerOpenPhoneContextMenu.swift` (TelegramUI): **Telefon raqam**: xatoda "Qayta urinish" va to'g'ri xabar chiqadi.

### Papkalar

132. `ChatListFilterPresetController.swift` (ChatListUI): papka muharririda "Ikonka" qatori (#18).
133. `FenixuzFolderIconPicker.swift` (ChatListUI, yangi fayl): emoji ikonka tanlash ekrani (#18).
134. `UserLimitsConfiguration.swift` (TelegramCore): papka limiti 1000.
135. `ChatListFilterPresetListController.swift` (ChatListUI): "Show Folder Tags" Premium'siz.
136. `ChatListController.swift` (ChatListUI): header tugmalari chevron ortiga yig'iladi.

### Qo'ng'iroqlar

137. `NotificationService.swift` (NotificationService): CallKit ishlamasa qo'ng'iroq ringtone bilan jiringlaydi.
138. `SharedAccountContext.swift`, `AppDelegate.swift` (TelegramUI): uxlayotgan accountga qo'ng'iroq kelsa account uyg'otiladi.
139. `Telegram/BUILD`: `INStartCallIntent` activity type.
140. `PresentationCall.swift` (TelegramCallsUI): qo'ng'iroq diagnostikasi uchun log qatori.

### Bildirishnomalar

141. `Telegram/BUILD`: Communication Notifications entitlement (push'da yuboruvchi rasmi).
142. `NotificationService.swift` (NotificationService): bo'sh yoki umumiy "new message" bannerlari chiqmaydi (yashirin boshlash, bo'sh content fallback, 20 s watchdog, xom bannerlarni tozalash).
143. `NotificationService.swift` (NotificationService): bo'sh xizmat bannerlari `fenixuz_blank` belgisi bilan tozalanadi.
144. `AppDelegate.swift` (TelegramUI): NSE boyitmagan bannerlar tozalanadi, `peerId` uchun fallback.
145. `SharedNotificationManager.swift` (TelegramUI): o'qilgan xabar bildirishnomasi har bir live accountda o'chadi.
146. `ApplicationContext.swift` (TelegramUI): faqat primary account uchun ishlaydigan eski tozalash olib tashlangan.
147. `NotificationsAndSoundsController.swift` (SettingsUI): "Barcha accountlardan bildirishnomalar" bo'limi doim ko'rinadi.

### Ilova va Settings

148. `PeerInfoSettingsItems.swift` (PeerInfoScreen): oltin "Novagram Settings", "Novagram Bots" va "Analytics" qatorlari (lokalizatsiya qilingan).
149. `PeerInfoScreenDisclosureItem.swift` (PeerInfoScreen): qator nomi uchun ixtiyoriy rang.
150. `PeerInfoScreen.swift`, `PeerInfoScreenSettingsActions.swift` (PeerInfoScreen): Bots va Analytics ekranlarini ochish.
151. `ItemListDisclosureItem.swift` (ItemListUI): Bots ro'yxatida avatar o'lchamini sozlash mumkin.
152. `AppDelegate.swift` (TelegramUI): Analytics ishga tushadi.
153. `PrivacyInfo.xcprivacy` (Telegram app): anonim Device ID (Analytics, tracking yo'q).
154. `FenixAnalyticsDuck.imageset` (TelegramUI, yangi asset): Analytics sahifasi rasmi.
155. `ApplicationContext.swift` (TelegramUI): birinchi launch'da Tips, keyingilarida App Store yangilanish tekshiruvi.
156. `AppDelegate.swift` (TelegramUI), `ThemeSettingsAppIconItem.swift` (SettingsUI): 7 ta Nova ikonka va ularning lokalizatsiya qilingan nomlari.
157. `Info.plist`, `Telegram/BUILD`, `Nova*Icon.alticon` (Telegram app): alternate ikonka fayllari.
158. `NavigationButtonComponent.swift` (TelegramUI), `ChatListController.swift` (ChatListUI): header va story kamera tugmalarida haptic.
159. `ItemListSwitchItem.swift` (ItemListUI): switch'dagi "NEW" badge joyi tuzatilgan.
224. `PeerInfoSettingsItems.swift` (PeerInfoScreen): Settings tab'ining eng pastida (`support` section ostida) ilova versiyasi — "Novagram 13.0 (85)". Matn `FenixuzAppVersion.displayText` (UpdateCheck moduli), hook — 1 qator `PeerInfoScreenCommentItem(id: 100, ...)` + `import FenixuzUpdateCheck` (2026-10-12).

### Brand va til

160. `PresentationData.swift` (TelegramPresentationData): server tarjimalaridagi "Telegram" so'zi "Novagram"ga almashtiriladi.
161. `en.lproj/Localizable.strings` (Telegram app): ichki matnlarda "Novagram" ("NOVAGRAM TONES" ham).
162. `InfoPlist.strings` (18 til), `InfoBazel.plist` (Telegram app): ruxsat so'rovlari matnida "Novagram".
163. `AppIntentVocabulary.plist` (19 til): Siri lug'atida "Novagram".
164. `Telegram/BUILD`: `bundle_name = "Novagram"`.
165. `CallKitIntegration.swift` (TelegramCallsUI): qo'ng'iroq ekranida "Novagram".
166. `Share/…/Localizable.strings`, `WidgetKitWidget/…/Localizable.strings`, `IntentHandler.swift`, `WidgetItems.swift`: Share, Widget va Siri matnlarida "Novagram".
167. `StoreDownloadedMedia.swift` (TelegramUI): Photos albomi "Novagram".
168. `DeviceContactData.swift` (AccountContext), `DeviceContactDataManager.swift` (TelegramUI), `IntentContacts.swift` (SiriIntents): kontakt label'i "Novagram", eski "Telegram" ham taniladi.
169. `AuthorizationSequenceSplashController.swift` (AuthorizationUI): Welcome ekranida brand rangi.
170. `RMIntroViewController.m` (RMIntro): simulator'da intro logosi.
171. `tgwatch Watch App/Info.plist` (WatchApp): watch ilovada "Novagram".
172. `SearchBarNode.swift` (SearchBarNode): xitoy tilida qidiruvdagi "x" tugmasi joyida turadi. **13.0: olib tashlandi, upstream bb5b4f5a3c o'zi tuzatgan.**
173. `TextProcessingTranslateContentComponent.swift` (TelegramUI): `zh-hans` → `zh`, shunda tarjima ishlaydi.
174. `LocalizationListControllerNode.swift` (SettingsUI): Settings → Language'da xitoy tili.
175. Telegram fayllaridagi Fenixuz matnlari (`ChatContextMenus`, `ChatController`, `ChatControllerNode`, `ChatInterfaceStateContextMenus` va boshqalar): `zh` tarjimasi qo'shilgan.

### Apple talablari

176. `InAppPurchaseManager.swift` (InAppPurchaseManager): StoreKit olib tashlangan, har bir xaridda alert chiqadi.
177. `AppDelegate.swift` (TelegramUI), `AuthorizationSequencePaymentScreen.swift` (AuthorizationUI): `import StoreKit` olib tashlangan, obunalar web'da boshqariladi.
178. `PeerInfoSettingsItems.swift` (PeerInfoScreen): to'lov bo'limi faqat ko'rish uchun.
179. `DeviceAccess.swift` (DeviceAccess): iOS Contacts ruxsatidan oldin rozilik dialogi (5.1.2).
180. `DeviceContactDataManager.swift` (TelegramUI): kontakt ruxsati bo'lmasa ham chat ochiladi.
181. `TelegramRootController.swift` (TelegramUI): Contacts tabi qayta yoqilgan.
182. `AuthorizationSequencePhoneEntryController.swift` (AuthorizationUI): demo raqamda SMS polling oldindan boshlanadi.
183. `AuthorizationSequenceCodeEntryController.swift`, `AuthorizationSequenceCodeEntryControllerNode.swift` (AuthorizationUI): demo kod avtomatik to'ldiriladi, "Kod kelmadimi?" yashiriladi.

### Crash fixlar (upstream xatolari)

184. `AnimatedStickerFrameSource.swift` (AnimatedStickerNode) va unga test: buzilgan sticker kesh fayli crash qilmaydi.
185. `EmojiHeaderComponent.swift`, `ReactionContextNode.swift`, `QuickShareToastScreen.swift`, `EmojiStatusSelectionComponent.swift`, `StoryItemSetContainerComponent.swift`: parabolik animatsiyada nolga bo'lish tuzatilgan.
186. `HLSVideoJSNativeContentNode.swift` (TelegramUniversalVideoContent): HLS range tekshiriladi.
187. `VolumeButtons.swift` (Utils): deinit main thread'da bajariladi.
188. `TGMediaPickerPhotoStripView.m` (LegacyComponents): media picker'da count mos kelmasa reload qilinadi. **13.0: olib tashlandi, upstream 37abd7a04a.**
189. `ChatInterfaceInputContexts.swift` (TelegramUI): eskirgan matn uzunligi tufayli bo'ladigan crash. **13.0: olib tashlandi, upstream f09120e85f.**
190. `SSubscriber.m` (SSignalKit): disposal race. **13.0: olib tashlandi, upstream 7f6f87843c.**
191. `PasskeysScreen.swift` (TelegramUI): `preconditionFailure` o'rniga anchor qaytariladi.
192. `NewContactScreen.swift` (TelegramUI): update re-entrancy.
193. `FFMpegMediaFrameSourceContext.swift`, `MediaPlayerNode.swift` (MediaPlayer): story video oxiridan o'tib ketganda Timer crash.
194. `LocationUtils.swift`, `LocationViewControllerNode.swift` (LocationUI): ETA shimmer qotib qolmaydi (ruxsat va timeout).
195. `OpenInOptionsScreen.swift` (OpenInExternalAppUI): "Open In" ikonkalari bosiladi (upstream cherry-pick). **13.0: upstream'da bor, hook yo'q.**

### BUILD dependency'lar

196. `AuthorizationUI/BUILD`: AppleReview, Brand, Localization, AutoProxy, BotTokenLogin.
197. `CallListUI/BUILD`: SecretVault.
198. `ChatListUI/BUILD`: StoryUnlock, ChatLock, SecretVault, ForeignUserBlock, Localization.
199. `ContactListUI/BUILD`: SecretVault, ChatLock.
200. `DeviceAccess/BUILD`: ContactsConsent.
201. `InAppPurchaseManager/BUILD`: AppStoreIAP (StoreKit davridagi deplar olib tashlangan).
202. `SettingsUI/BUILD`: PremiumUnlock, Localization.
203. `TelegramPresentationData/BUILD`: Brand.
204. `TelegramUI/BUILD`: PremiumUnlock, StoryUnlock, ChatLock, SecretVault, ForeignUserBlock, EditedHistory, Localization, Tips, UpdateCheck, UnreadReminder, ProMessager, Analytics, AutoProxy, ForwardEdit.
205. `ChatMessageDateAndStatusNode/BUILD`: Localization.
206. `ChatTextInputPanelNode/BUILD`: SpeechToText, Localization, RoundVideoFromGallery.
207. `GlobalControlPanelsContext/BUILD`: clean.
208. `PeerInfoScreen/BUILD`: ProMessager, Localization, Analytics, UpdateCheck (versiya footer'i, #224).
209. `StoryContainerScreen/BUILD`: StoryUnlock.
210. `TranslateHeaderPanelComponent/BUILD`: PremiumUnlock.
211. `AnimatedStickerNode/BUILD`: unit test target'lari.

### Build

212. `Telegram/BUILD`: minimum iOS 15.0, widget uchun ham. **13.0: upstream ham 15.0; widget genrule olib tashlangan.**
213. 39 ta `BUILD` fayl: iOS 15 deprecation'lari error emas, warning bo'ladi.
214. `sqlcipher/BUILD`: Xcode 26.5 SDK uchun `sqlite3ext.h` private qilingan.
215. `run.sh`: device build'da push entitlement (`aps_environment`).
216. `Telegram/BUILD`: upstream watch app qaytarilganda fork sozlamalari saqlab qolingan (`composer_icon_folders = []`, `:PrivacyManifest`).
217. `project.yml`, `project.pbxproj` (WatchApp): Team ID `ZDBP5RSRZF`.
218. `ChatInputTextNode.swift` (TelegramUI): input diagnostika log'i (faqat DEBUG).
219. `run.sh`: Xcode versiyasi o'rnatilgan Xcode'dan olinadi, Swift 6.4 warning'lari error bo'lmaydi.
220. `ChatControllerNode.swift` (TelegramUI): Swift 6.4 uchun `EmptyInputView` importi aniqlashtirilgan. **13.0: olib tashlandi, upstream `EmptyKeyboardInputView` (fdcd002ef5).**
221. `AppDelegate.swift` (TelegramUI), `Telegram/BUILD`, `TelegramUI/BUILD`: UIScene life cycle (`NovagramSceneDelegate`), iOS 27 SDK bilan ilova ochilishi uchun. **13.0: olib tashlandi, upstream `SceneDelegate` (13a2694420); `Fenixuz/SceneLifecycle` o'chirildi.**
222. `UIViewController+Navigation.m` (UIKitRuntimeUtils): iOS 27'da yashirin klaviatura API chaqirilmaydi, ilova ishga tushganda to'xtamaydi. **13.0: olib tashlandi, upstream 93af3a138e.**
223. `publish.sh`, `release.sh`: App Store build uchun Swift 6.4 flag'lari.
