let browserMarkup = '';
function refreshBrowser() {
  const markup = render();
  if (markup === browserMarkup) return;
  browserMarkup = markup;
  const root = document.querySelector('.game'), oldStage = root.querySelector('[data-3d]');
  const template = document.createElement('template'); template.innerHTML = markup;
  const next = template.content.firstElementChild, nextStage = next.querySelector('[data-3d]');
  if (oldStage && nextStage) nextStage.replaceWith(oldStage);
  root.replaceWith(next);
}
document.addEventListener('click', event => {
  const target = event.target.closest('[data-action]');
  if (!target) return;
  onAction(target.dataset.action, target.dataset.value); refreshBrowser();
});
document.addEventListener('keydown', event => {
  if (['INPUT', 'TEXTAREA'].includes(event.target.tagName) || event.metaKey || event.ctrlKey || event.altKey) return;
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'w', 'a', 's', 'd', 'Escape'].includes(event.key)) { event.preventDefault(); onKey(event.key); refreshBrowser(); }
});
function refreshLoop() { refreshBrowser(); requestAnimationFrame(refreshLoop); }
requestAnimationFrame(refreshLoop);
updateTelegramLink();
(async () => {
  try {
    const route = location.pathname.split('/').filter(Boolean);
    if (route[0] === 'watch') await voxelJoinLink(location.href);
    else if (route[0] === 'play') {
      if (sessionStorage.getItem('voxel.name')) await voxelJoinLink(location.href);
      else showEntry('join');
    } else showEntry('create');
  } catch (error) { showEntry('link', error.message); voxelError(error); }
})();
