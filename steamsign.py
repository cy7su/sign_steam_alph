#Игнорируем тип данных для переменных чтобы не выдавало ошибку
#type:ignore  #далешь так и спина болеть не будет)

#импортируем библиотеки для работы авто входа, имулирует нажатие клавиатуры и мыши
import pyautogui 
import time 
import cv2

login = 'fan_al'
password = 'NQRTHRFRYY4H'



pyautogui.hotkey('winleft')

pyautogui.sleep(3)

pyautogui.write('Steam')

pyautogui.sleep(3)

pyautogui.press('enter')

pyautogui.sleep(10)

steam_plus = ("plussteam.png")
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
