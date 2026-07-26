(async function () {

    if (settings.Modes == "Alt+F4") {
        await QuitGame();
    } else if (settings.Modes == "完全退出游戏") {
        await ExitGame();
    } else if (settings.Modes == "完全退出游戏到桌面") {
        await ExitGametoDesktop();
    } else {
        log.info("尖尖哇嘎乃")
    }

    async function QuitGame() {
        keyDown("MENU");
        keyDown("F4");
        await sleep(50);
        keyUp("MENU");
        keyUp("F4");
        await sleep(1500);
    }

    async function ExitGame() {
        setGameMetrics(3840, 2160, 2)
        keyPress("VK_ESCAPE");
        await sleep(1000);
        click(90, 2000);
        await sleep(1000);
        click(2100, 1080);
        await sleep(10000);
        click(192, 1970);
        await sleep(1000);
        click(2150, 1150);
        await sleep(1000);
    }

    async function ExitGametoDesktop() {
        setGameMetrics(3840, 2160, 2)
        keyPress("VK_ESCAPE");
        await sleep(1000);
        click(90, 2000);
        await sleep(1000);
        click(2100, 1300);
    }
})();
