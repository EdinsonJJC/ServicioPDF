import schedule
import time
from orchestrator import Orchestrator


def main():
    bot = Orchestrator()
    bot.procesar_todo([])


if __name__ == "__main__":
    main()

    schedule.every(5).minutes.do(main)
    # schedule.every().day.at("07:00").do(main)  
    # schedule.every().day.at("12:00").do(main)  
    # schedule.every().day.at("21:00").do(main)  
    
    while True:
        schedule.run_pending()
        time.sleep(60)