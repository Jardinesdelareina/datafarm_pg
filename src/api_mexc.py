import threading
import _thread
import json
import websocket
import datetime
from src.db import cursor, connection
from src.symbol_list import symbol_list

deals_list = []


class SocketConnection(websocket.WebSocketApp):

    def __init__(self, url, params=[]):
        super().__init__(url=url, on_open=self.on_open)
        self.params = params
        self.on_message = lambda ws, msg: self.message(msg)
        self.on_close = lambda ws: print('Closing')
        self.run_forever()


    def on_open(self, ws):
        def run(*args):
            tradeStr = {"method": "SUBSCRIPTION", "params": self.params}
            ws.send(json.dumps(tradeStr))
        _thread.start_new_thread(run, ())


    def message(self, msg): 
        global deals_dict, symbols_list
        json_data = json.loads(msg)
        time = datetime.datetime.fromtimestamp(json_data['t'] / 1000)
        formatted_time = time.strftime('%Y-%m-%d %H:%M:%S')
        symbol = json_data['s']
        price = json_data['d']['p']
        print(symbol, ' | ', formatted_time, ' | ', price)
        cursor.execute(
            """
                INSERT INTO market.tickers(fk_symbol, t_time, t_price) 
                VALUES(%s, %s, %s)
            """,
            (symbol.lower(), formatted_time, float(price))
        )
        connection.commit()


for i in symbol_list:
    cursor.execute(f"INSERT INTO market.currencies(symbol) VALUES('{i.lower()}')")
    connection.commit()
    threading.Thread(
        target=SocketConnection, 
        args=('wss://wbs.mexc.com/ws', [f'spot@public.miniTicker.v3.api@{i}@UTC+8'])
    ).start()
