/**
 * KisakiGals Locale Emulator 转区启动插件入口（v1.0.0）
 * 原项目地址：https://github.com/xupefei/Locale-Emulator
 */
module.exports = {
  id: 'locale-emulator',

  onInit(ctx) {
    const lePath = String(ctx.config.le_path || '').trim();
    const fallback = ctx.config.fallback_normal !== false;
    ctx.log(
      `locale-emulator v1.0.0 initialized (le_path=${lePath || '(unset)'}, fallback_normal=${fallback})`
    );
  },

  onGameLaunch(ctx, payload) {
    const lePath = String(ctx.config.le_path || '').trim();
    const gameId = payload && payload.gameId != null ? payload.gameId : '?';
    ctx.log(`onGameLaunch gameId=${gameId}, le_path=${lePath || '(unset)'}`);
  },

  onDispose() {
    // 无需额外清理系统句柄
  }
};
