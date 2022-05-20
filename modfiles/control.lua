-- As functions can't be stored in global, references to them can't be stored in modal_data
-- for some of the mod's generic interfaces. Instead, a name needs to be passed, and the
-- function needs to be stored (on file parse) in one of these tables.
NTH_TICK_HANDLERS = {}
GENERIC_HANDLERS = {}
SEARCH_HANDLERS = {}
TUTORIAL_TOOLTIPS = {}

DEVMODE = true  -- enables certain conveniences for development
MARGIN_OF_ERROR = 1e-8  -- the margin of error for floating point calculations
TIMESCALE_MAP = {[1] = "second", [60] = "minute", [3600] = "hour"}
SUBFACTORY_DELETION_DELAY = 15 * 60 * 60 -- ticks to deletion after subfactory trashing
MODAL_SEARCH_LIMITING = 10  -- ticks between modal search runs
RECIPEBOOK_API_VERSION = 4  -- the API version of Recipe Book this mod works with
NEW = nil  -- global variable used to store new prototype data temporarily for migration

require("util")  -- core.lualib
fancytable = require('__flib__.table')  -- has more functionality than built-in table

translator = require("__flib__.dictionary")  -- translation module for localised search
--translator.set_use_local_storage(true)

require("data.init")
require("data.data_util")

require("ui.dialogs.main_dialog")
require("ui.dialogs.compact_dialog")
require("ui.dialogs.modal_dialog")
require("ui.ui_util")
require("ui.event_handler")

-- Some magic numbers to determine and calculate the dimensions of the main dialog
FRAME_SPACING = 12

TITLE_BAR_HEIGHT = 28
SUBFACTORY_SUBHEADER_HEIGHT = 36
SUBFACTORY_LIST_ELEMENT_HEIGHT = 28
SUBFACTORY_INFO_HEIGHT = 175

SUBFACTORY_LIST_WIDTH = 300
ITEM_BOX_BUTTON_SIZE = 40
ITEM_BOX_MAX_ROWS = 5
-- The following must remain 12, otherwise the scrollbar will not fit
-- The scroll pane style used for the item boxes is hardcoded at 12 for this reason
ITEM_BOX_PADDING = 12

TUTORIAL_EXPORT_STRING = "eNrtGdtq2zD0V4ae4y7OutEF9rKxwmCDsT6WYmT5ONUmWZokh4bgf9+RLScmSUncpk3LDHmwj879LmdJpMqSORjLVUGmJD6Lz85jMiJwp5VxCZ5acGS6JCm1EBDef0SEXPAU38dnMf78O2VOmYUWtCjArFlVI2LLtDnlYMn0ekkKKj2vay5nn7gD+VYblZXMoQ6RZRwKBpGm7M/Nm693VGoByN9xCZZRfJ5+GI9IoZxnRvDkZ0PslVTpb2CuEYI8nfLAIO0eGcjAcpTBcw4ZmTpTAgpbaE/idfMGUKnKAgXEFyjZwN+SG8iSFrokGeS8QEi6QKIA3qBKQbgkqJRTYQHZOqUTAXMQrVgmqPVGtRZVN6NgUtIeffMqrTG/KCGgNooEhrlQynilvqNKmz5pyeqzJjA90A0wrmukx/iWUQczzBQkY4bmjhczr/uaRRK830CgY+2vRgEfEcScQ8syU1732q3ICAyDwtEZguIxul5SdhuM29Qb2YJMBaoQBazoXR+lc4WyEsEldyv5WDKlgCSUTfNmD03OOXeLqKHZr0mXqJum52uP/ahZ7UqkcHJfKgUr2IojSO0WiRXKWzDelHCF1lYdYHB55ROfMt9atm0OJ3uMzHUSEDsWXjzQzVYDZAf7t8buip0c3bGTno79HFxRjXpUp6FcvMZSnDx9KS6rx8VvvBG/yaGF0SuA3PjG6vhzd9TmeYjicaIIXr7hLMpLU9A6DENJvtZg7hjYQzwfNIYnr3AMr3NmW3BInd1iw7rfseCyXsD7JR/N5hR37Cxi3LCSu2HPHvbsYc8++Z7dDHhV4Ig/SWEO69oxJzxTGl0ZMZo+92gf4njMOFoHICIt0PK9jUiCOOmc7HtF6Cr8MmfkC9rVhhn5AmakdVgbUWoO+JZx3Grs31SbxnGkSsxLv/fvEKIEz6L6dF+/vgXJGRXdEFx6uuoUvXr8NB+6pFaYISaq02SfR1JqsVXWHjxVjqwatuSFn76Z4UL01Pv/uVbHT3ytjreu1WvAVfsnJI6nm+ofpk78XQ=="

if DEVMODE then
    require("llog")
    LLOG_EXCLUDES = {}

    DEV_EXPORT_STRING = "eNrtWV9v2jAQ/ypTngkjaZk6pL1saqVJmzStjxWKHOdCvdlxZjuoCPHdd06cQoEWQtNCt0g8EPvu/Lv/52TuCZlEU1CaycwbeUE/6J8HXs+Du1wqE+GuBuON5l5MNDiC4UckSDmL8XnQD/Bnnwk1Us1yTrIM1FLUoufpIq52GWhvdDP3MiKsrBsmJp+YAfGeKZn5yGpg/A5lGSZAU8KR6MOg52XSWEYPd34omRS0BCTjX0BNJTBX0ki76CQDxy2UyahPmaIFM8irmcg5Sxkk3sioAvCcWW6pLQSLkwhZZCj7fICHKvhTMAVJVK/OvQRSluFKPEMmt7zGFQM3kUOTEq4BxRqZRxymwOtjKSfa6lMrs+htalAokrFC+OHZsAn0Q4AHbeIuPSkVtAza4tMrmAf94UPQ9wAMGk7b2PXt9hYYi0NV42xya3zJ+FO6pbxgyXM9Eg7bdIk2QMSLYw4Gh8f/uOeyOaq3vtoQWVJ+kdxmtK1RTmDKpVQW1TfEtF4OarZyz+pCWV4SHVgnKBamCRY35KCKpIZlE4sjr/AjqshZslqBFeQ/q7OtcZFyCrXIRFrYpYlQECgKmSETKO3Y8wSht06vdcgoFkTMEYLvqPywCehU4lkRZwJ1rc/HKl9wiFylr570A6POFxsu+l6SPeokJ5PeRxSI3MwizaWVFy7ZKjnXYIN3uegMsNgSG86r2491gRYs96/KSFmRfV23o1mZLhvNaOlWX1MGGQU/J/T3+N3lHUEjQxsN6pEzmlTN4OKgNL041Sy1U0IrSd3Etiee2Wcvn9lPBOeUmZlf8exGssr0YJhaz/RtgdSolpyv1ZLBvrXEBj6hds7d1Nnt7FAyzSNHuKLhxYFm1jlAsrd9S+rVY8PWDRs2NOxnZwpbRffOTkUeGaC6Jnu8JtvEgeWErw177Ypa/e+82I4Xq8kX5960UBmh0KXkG3bmlobd+fOgNhy+wTb83LtSuHFXahR8JJkSnLGTt3yD7ubsbs7+x+bsY7/a6sa1Njs8lTma0qckfu3W3vmxTT9qA8CrL107C5EAftQ+2fSKsAr4NHvkCc1qXY88gR6pDeaGH6s93mW0m43Ni2pVOFrKxLSwc/+WQyRniV/u7qrXtyAYJXzVBVeWb3GMWj14mRddIpcYIcovw2SXRWKisVSWFjxWjNwXbMEy230TxThviPv/uVYHJ/cJ8tLCa/x1cUsyPeO73BZpbSo7XvwF1fCNsQ=="
end
