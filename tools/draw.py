import schemdraw
import schemdraw.elements as elm
from schemdraw.elements import IcPin

schemdraw.config(fontsize=11)
d = schemdraw.Drawing(show=False)

mcu = d.add(elm.Ic(pins=[
    IcPin(name='PA2 / USART2_TX', side='left', anchorname='TX'),
    IcPin(name='PA3 / USART2_RX', side='left', anchorname='RX'),
    IcPin(name='GND', side='left', anchorname='GNDL'),
    IcPin(name='PB13 / SPI2_SCK', side='right', anchorname='SCK'),
    IcPin(name='PB14 / SPI2_MISO', side='right', anchorname='MISO'),
    IcPin(name='PB15 / SPI2_MOSI', side='right', anchorname='MOSI'),
    IcPin(name='PB12 / GPIO (CS_SD)', side='right', anchorname='CS1'),
    IcPin(name='PB11 / GPIO (CS_BME)', side='right', anchorname='CS2'),
    IcPin(name='3V', side='right', anchorname='V3'),
    IcPin(name='GND', side='right', anchorname='GND'),
], pinspacing=1.2, edgepadW=11, edgepadH=0.6, plblsize=11, lofst=0.2,
   ).at((0, 0)))

# Place the adapter so its RX lead lines up with the MCU TX lead. Both
# sides use pinspacing 1.2, so TX/RX and the grounds are horizontal too.
# Schemdraw lists pins bottom-to-top, so RX is the lowest adapter pin.
uart = d.add(elm.Ic(pins=[
    IcPin(name='RX', side='right', anchorname='RX'),
    IcPin(name='TX', side='right', anchorname='TX'),
    IcPin(name='GND', side='right', anchorname='GND'),
], pinspacing=1.2, edgepadW=1.6, edgepadH=0.7, lofst=0.18,
   ).anchor('RX').at((mcu.TX[0] - 4.2, mcu.TX[1])))

mcu_bb = mcu.get_bbox()
sd = d.add(elm.Ic(pins=[
    IcPin(name='VCC', side='left', anchorname='V3'),
    IcPin(name='GND', side='left', anchorname='GND'),
    IcPin(name='SCK', side='left', anchorname='SCK'),
    IcPin(name='MISO', side='left', anchorname='MISO'),
    IcPin(name='MOSI', side='left', anchorname='MOSI'),
    IcPin(name='CS', side='left', anchorname='CS'),
], pinspacing=1.0, edgepadW=2.6, edgepadH=0.5).at((mcu_bb.xmax + 14, 6.5)))

bme = d.add(elm.Ic(pins=[
    IcPin(name='VIN', side='left', anchorname='V3'),
    IcPin(name='GND', side='left', anchorname='GND'),
    IcPin(name='SCK', side='left', anchorname='SCK'),
    IcPin(name='SDO (MISO)', side='left', anchorname='MISO'),
    IcPin(name='SDI (MOSI)', side='left', anchorname='MOSI'),
    IcPin(name='CS', side='left', anchorname='CS'),
], pinspacing=1.0, edgepadW=2.6, edgepadH=0.5).at((mcu_bb.xmax + 14, -3.5)))

colors = {
    'SCK': '#d62728', 'MISO': '#1f77b4', 'MOSI': '#2ca02c',
    'V3': '#ff7f0e', 'GND': 'black', 'CS1': '#9467bd', 'CS2': '#8c564b',
}
ex = mcu.SCK[0]
busx = {
    'V3': ex + 1.5, 'GND': ex + 2.5, 'SCK': ex + 3.7, 'MISO': ex + 4.9,
    'MOSI': ex + 6.1, 'CS1': ex + 7.3, 'CS2': ex + 8.5,
}

for net, x in busx.items():
    p = getattr(mcu, net)
    c = colors[net]
    d.add(elm.Line(color=c).at(p).to((x, p[1])))
    if net in ('V3', 'GND', 'SCK', 'MISO', 'MOSI'):
        targets = [getattr(sd, net), getattr(bme, net)]
    elif net == 'CS1':
        targets = [sd.CS]
    else:
        targets = [bme.CS]
    ys = [p[1]] + [t[1] for t in targets]
    d.add(elm.Line(color=c).at((x, min(ys))).to((x, max(ys))))
    for t in targets:
        d.add(elm.Line(color=c).at((x, t[1])).to(t))
        if len(targets) > 1:
            d.add(elm.Dot(color=c).at((x, t[1])))

def link(a, b, color):
    if abs(a[1] - b[1]) < 0.05:
        d.add(elm.Line(color=color).at(a).to(b))
    else:
        mid = (a[0] + b[0]) / 2.0
        d.add(elm.Line(color=color).at(a).to((mid, a[1])))
        d.add(elm.Line(color=color).at((mid, a[1])).to((mid, b[1])))
        d.add(elm.Line(color=color).at((mid, b[1])).to(b))

link(mcu.TX, uart.RX, '#e377c2')
link(mcu.RX, uart.TX, '#17becf')
link(mcu.GNDL, uart.GND, 'black')

def abs_bbox(el):
    return el.get_bbox(transform=True, includetext=True)

def top(el, txt, dy=0.85):
    bb = abs_bbox(el)
    d.add(elm.Label().at(((bb.xmin + bb.xmax) / 2, bb.ymax + dy)).label(
        txt, fontsize=13))

top(mcu, 'STM32F4 Discovery (STM32F407VG)')
top(uart, '3.3 V USB-UART adapter', dy=1.15)
uart_bb = abs_bbox(uart)
d.add(elm.Label().at(((uart_bb.xmin + uart_bb.xmax) / 2, uart_bb.ymax + 0.42)).label(
    '3.3 V levels only, no 5 V', fontsize=10, color='#a00000'))
d.add(elm.Label().at((sd.CS[0] + 2.4, sd.CS[1] + 1.1)).label(
    'microSD card reader (3.3 V)', fontsize=13))
d.add(elm.Label().at((bme.CS[0] + 2.4, bme.CS[1] + 1.1)).label(
    'BME280 weather sensor (SPI mode)', fontsize=13))

note_y = min(abs_bbox(el).ymin for el in d.elements) - 0.4
d.add(elm.Label().at((mcu_bb.xmin, note_y)).label(
    'Notes: SPI1 (PA5/PA6/PA7) is taken by the onboard LIS3DSH accelerometer, so the shared bus uses SPI2.\n'
    'Both devices share SCK/MISO/MOSI; each has its own chip-select, driven high when idle.\n'
    'Add 10 k\u03a9 pull-ups to 3V on both CS lines and on MISO. Use a 3.3 V microSD breakout (or a 5 V one with its own regulator and level shifter).\n'
    'USART2 is PA2 (TX) and PA3 (RX), AF7, 115200 8N1. PA2 goes to the adapter RX, PA3 comes from the adapter TX, and the grounds are tied together.\n'
    'Use a 3.3 V USB-UART adapter only. A 5 V adapter will damage the MCU pins.',
    halign='left', valign='top', fontsize=10))
d.save('stm32f4_spi_schematic.png', dpi=160)
