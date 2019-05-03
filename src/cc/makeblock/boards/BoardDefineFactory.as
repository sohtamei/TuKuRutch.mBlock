package cc.makeblock.boards
{
	public class BoardDefineFactory
	{
		static public function GetMBot():BoardDefine
		{
			var board:BoardDefine = new BoardDefine();
			board.addPortDefine(1, "Port1", BlockFlag.PORT_YELLOW | BlockFlag.PORT_BLUE | BlockFlag.PORT_WHITE);
			board.addPortDefine(2, "Port2", BlockFlag.PORT_YELLOW | BlockFlag.PORT_BLUE | BlockFlag.PORT_WHITE);
			board.addPortDefine(3, "Port3", BlockFlag.PORT_YELLOW | BlockFlag.PORT_BLUE | BlockFlag.PORT_WHITE | BlockFlag.PORT_BLACK);
			board.addPortDefine(4, "Port4", BlockFlag.PORT_YELLOW | BlockFlag.PORT_BLUE | BlockFlag.PORT_WHITE | BlockFlag.PORT_BLACK);
			board.addPortDefine(9,  "M1", BlockFlag.PORT_RED);
			board.addPortDefine(10, "M2", BlockFlag.PORT_RED);
			return board;
		}
	}
}