#импорт библиотек , первая нужна для эммуляции клавы и мыши , втораяая
import pyautogui
import mouse
import keyboard


steam_plus = ("plussteam.png")

login = 'fan_al'
password = 'NQRTHRFRYY4H'

pyautogui.hotkey('winleft')

pyautogui.sleep(3)

pyautogui.write('Steam')

pyautogui.sleep(3)

pyautogui.press('enter')

pyautogui.sleep(7)

try: 
    plus = pyautogui.locateOnScreen(steam_plus, confidence= 0.6)
    
    pyautogui.sleep(5)

    pyautogui.click(plus)

    pyautogui.sleep(5)

    pyautogui.write(login)

    pyautogui.sleep(5)

    pyautogui.press('tab')

    pyautogui.write(password)

    pyautogui.sleep(5)

    pyautogui.press('enter')
except:
    pyautogui.write(login)

    pyautogui.press('tab')

    pyautogui.write(password)

    pyautogui.press('enter')