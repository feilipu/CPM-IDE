;
; Copyright (c) 2018 Phillip Stevens (feilipu)
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;

INCLUDE "config_rc2014_private.inc"

SECTION rodata_driver

EXTERN  _cpm_sio_interrupt_vector_table

PUBLIC  __sio_init_async_rodata

__sio_init_async_rodata:

    defb    __siob_init_async_rodata_end-__siob_init_async_rodata_begin
    defb    __IO_SIOB_CONTROL_REGISTER
__siob_init_async_rodata_begin:
    defb    __IO_SIO_WR0_CHANNEL_RESET
    defb    __IO_SIO_WR0_R2
    defb    _cpm_sio_interrupt_vector_table&$F0
    defb    __IO_SIO_WR0_R4|__IO_SIO_WR0_EXT_INT_RESET
    defb    __IO_SIO_WR4_CLK_DIV_64|__IO_SIO_WR4_STOP_2|__IO_SIO_WR4_PARITY_NONE
    defb    __IO_SIO_WR0_R3
    defb    __IO_SIO_WR3_RX_8BIT|__IO_SIO_WR3_RX_ENABLE
    defb    __IO_SIO_WR0_R5
    defb    __IO_SIO_WR5_TX_DTR|__IO_SIO_WR5_TX_8BIT|__IO_SIO_WR5_TX_ENABLE|__IO_SIO_WR5_RTS
    defb    __IO_SIO_WR0_R1|__IO_SIO_WR0_EXT_INT_RESET
    defb    __IO_SIO_WR1_RX_INT_ALL|__IO_SIO_WR1_B_STATUS_VECTOR|__IO_SIO_WR1_TX_INT_ENABLE
__siob_init_async_rodata_end:

    defb    __sioa_init_async_rodata_end-__sioa_init_async_rodata_begin
    defb    __IO_SIOA_CONTROL_REGISTER
__sioa_init_async_rodata_begin:
    defb    __IO_SIO_WR0_CHANNEL_RESET
    defb    __IO_SIO_WR0_R4|__IO_SIO_WR0_EXT_INT_RESET
    defb    __IO_SIO_WR4_CLK_DIV_64|__IO_SIO_WR4_STOP_2|__IO_SIO_WR4_PARITY_NONE
    defb    __IO_SIO_WR0_R3
    defb    __IO_SIO_WR3_RX_8BIT|__IO_SIO_WR3_RX_ENABLE
    defb    __IO_SIO_WR0_R5
    defb    __IO_SIO_WR5_TX_DTR|__IO_SIO_WR5_TX_8BIT|__IO_SIO_WR5_TX_ENABLE|__IO_SIO_WR5_RTS
    defb    __IO_SIO_WR0_R1|__IO_SIO_WR0_EXT_INT_RESET
    defb    __IO_SIO_WR1_RX_INT_ALL|__IO_SIO_WR1_TX_INT_ENABLE
__sioa_init_async_rodata_end:

    defb    $00                 ; NULL terminator

