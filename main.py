import sys
import time
from pathlib import Path

# - Работа с WinAPI для эмуляции клавиатуры/мыши и управления окнами
import win32api as api
import win32con as con
import win32gui as gui

# - Работа с изображениями: скриншоты и поиск шаблонов
from PIL import ImageGrab, ImageChops, Image, ImageStat

# - Логирование в файл с ротацией
from loguru import logger

# - Используется для простого ADT и проверки типов
from attrs import define
from beartype import beartype

# - Стандартный product для генерации пар координат
from itertools import product

# - Настройки таймингов и файлов шаблонов
TYPE_DELAY = 0.02
FOCUS_DELAY = 0.1
WINDOW_CLASS = "SDL_app"
BUTTON_FILE = Path("button.png")
CROSS_FILE = Path("cross.png")
TEMPLATE_THRESHOLD = 0.86

# - Класс для хранения учетных данных пользователя
@define
class Credentials:
    username: str
    password: str

@beartype
def type_string(text: str):
    # - Ввод текста по символам через VkKeyScan
    # - Автоматически определяет необходимость Shift
    for ch in text:
        vk = api.VkKeyScan(ch)
        #! Если символ не поддерживается VkKeyScan, он пропускается
        if vk == -1:
            continue
        vk_code = vk & 0xFF
        shift = (vk >> 8) & 0x01
        if shift:
            api.keybd_event(con.VK_SHIFT, 0, 0, 0)
        api.keybd_event(vk_code, 0, 0, 0)
        api.keybd_event(vk_code, 0, con.KEYEVENTF_KEYUP, 0)
        if shift:
            api.keybd_event(con.VK_SHIFT, 0, con.KEYEVENTF_KEYUP, 0)
        time.sleep(TYPE_DELAY)

@beartype
def press_key(vk: int, shift: bool = False):
    # - Нажатие клавиши с возможным удержанием Shift
    if shift:
        api.keybd_event(con.VK_SHIFT, 0, 0, 0)
    api.keybd_event(vk, 0, 0, 0)
    api.keybd_event(vk, 0, con.KEYEVENTF_KEYUP, 0)
    if shift:
        api.keybd_event(con.VK_SHIFT, 0, con.KEYEVENTF_KEYUP, 0)

@beartype
def find_window(class_name: str):
    #! Если окно не найдено, sys.exit завершает весь скрипт
    # - Поиск окна по имени класса
    hwnd = gui.FindWindow(class_name, None)
    if not hwnd:
        logger.error("Window not found")
        sys.exit(1)
    # - Восстановление и установка окна на передний план
    gui.ShowWindow(hwnd, con.SW_RESTORE)
    gui.SetForegroundWindow(hwnd)
    time.sleep(FOCUS_DELAY)
    return hwnd

@beartype
def get_window_rect(hwnd: int):
    # - Получение координат окна: (left, top, right, bottom)
     #! Если hwnd неверный или окно закрылось, gui.GetWindowRect может выкинуть ошибку
    return gui.GetWindowRect(hwnd)

@beartype
def screenshot(hwnd: int):
    # - Сделать скриншот области окна
    #! ImageGrab может работать некорректно при высоком DPI или на нескольких мониторах
    return ImageGrab.grab(bbox=get_window_rect(hwnd))

# - Кеширование шаблонов для ускорения работы
TEMPLATE_CACHE = {}

@beartype
def match_template(region_img: Image.Image, template_path: Path, threshold: float = TEMPLATE_THRESHOLD):
    # - Поиск шаблона в изображении
    #! Если шаблон не найден, возвращаем None, что может вызвать пропуск клика
    if not template_path.exists():
        logger.warning(f"Template {template_path} not found")
        return None
    if template_path not in TEMPLATE_CACHE:
        TEMPLATE_CACHE[template_path] = Image.open(template_path).convert("RGB")
    template = TEMPLATE_CACHE[template_path]
    region_img = region_img.convert("RGB")
    t_w, t_h = template.size
    s_w, s_h = region_img.size
    step = 5

    #! Если окно закрылось между скрином и кликом, SetCursorPos или mouse_event может вызвать ошибку
    # - Перебор всех возможных координат шаблона с шагом step
    for x, y in product(range(0, s_w - t_w, step), range(0, s_h - t_h, step)):
        crop = region_img.crop((x, y, x + t_w, y + t_h))
        diff = ImageChops.difference(template, crop)
        avg_diff = sum(ImageStat.Stat(diff).mean) / 3
        if avg_diff < 255 * (1 - threshold):
            # - Возвращаем координаты центра шаблона
            return x + t_w // 2, y + t_h // 2
    return None

@beartype
def click_template(hwnd: int, region_img: Image.Image, template_path: Path):
    # - Найти шаблон и кликнуть по его центру
    #! Нет проверки, что курсор в правильном поле; если окно неактивно, ввод может пойти не туда
    pos = match_template(region_img, template_path)
    if pos:
        l, t, _, _ = get_window_rect(hwnd)
        api.SetCursorPos((l + pos[0], t + pos[1]))
        api.mouse_event(con.MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        api.mouse_event(con.MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
        return True
    return False

@beartype
def template_visible(region_img: Image.Image, template_path: Path):
    # - Проверка, виден ли шаблон
    return match_template(region_img, template_path) is not None

@beartype
def input_credentials(creds: Credentials):
    # - Ввод логина и пароля
    type_string(creds.username)
    press_key(con.VK_TAB)
    time.sleep(FOCUS_DELAY)
    type_string(creds.password)
    press_key(con.VK_RETURN)
    logger.info("Credentials entered")

def main():
    # - Парсинг аргументов командной строки
    args = sys.argv
    if "-u" not in args or "-p" not in args:
        logger.error("Missing username or password")
        sys.exit(1)

    creds = Credentials(
        username=args[args.index("-u") + 1], password=args[args.index("-p") + 1]
    )
    hwnd = find_window(WINDOW_CLASS)
    max_retries = 3
    attempt = 0
    success = False

    img = screenshot(hwnd)

    # - Проверка кнопки логина сразу
    if BUTTON_FILE.exists() and template_visible(img, BUTTON_FILE):
        logger.info("Login button detected, entering credentials")
        input_credentials(creds)
        success = True
    else:
        # - Если кнопка не найдена, ищем крестик и повторяем попытки
        while attempt < max_retries and not success:
            if CROSS_FILE.exists() and click_template(hwnd, img, CROSS_FILE):
                logger.info("Clicked cross to close overlay")
                time.sleep(FOCUS_DELAY)
            img = screenshot(hwnd)
            if BUTTON_FILE.exists() and template_visible(img, BUTTON_FILE):
                logger.info(f"Login button detected after cross click, entering credentials (attempt {attempt + 1})")
                input_credentials(creds)
                success = True
                break
            attempt += 1
            logger.warning(f"Login button not detected, retrying ({attempt}/{max_retries})")
            time.sleep(0.3)

    if not success:
        logger.error("Login button not detected after maximum retries, aborting")

if __name__ == "__main__":
    main()
