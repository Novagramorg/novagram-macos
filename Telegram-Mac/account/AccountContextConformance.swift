#if SHARE
import TelegramContextShare
#else
import TelegramContext
#endif

extension AccountContext: AccountContextProtocol {}
