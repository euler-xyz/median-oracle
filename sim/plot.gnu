reset

#set terminal wxt size 800,600 enhanced font 'Verdana,9' persist

set terminal pngcairo size 800,600 enhanced font 'Verdana,9'
set output 'output.png'



set datafile separator comma


# define axis
# remove border on top and right and set color to gray
set style line 11 lc rgb '#808080' lt 1
set border 3 back ls 11
set tics nomirror
# define grid
set style line 12 lc rgb '#808080' lt 0 lw 1
set grid back ls 12

# color definitions
#set style line 1 lc rgb '#8b1a0e' pt 1 ps 1 lt 1 lw 2 # --- red
#set style line 2 lc rgb '#5e9c36' pt 6 ps 1 lt 1 lw 2 # --- green

set style line 1 linecolor rgb '#0060ad' linetype 1 linewidth 3
set style line 2 linecolor rgb '#dd3033' linetype 1 linewidth 3
set style line 3 linecolor rgb '#0df023' linetype 1 linewidth 3
set style line 4 linecolor rgb '#813033' linetype 1 linewidth 2
set style line 5 linecolor rgb '#d130d3' linetype 1 linewidth 2
set style line 6 linecolor rgb '#57ccc7' linetype 1 linewidth 2



set xdata time
set timefmt "%s"
set format x "%Y-%m-%d\n%H:%M:%S"
set key Left center top reverse box samplen 2 width 2


## Quantisation plots

#set title "Quantisation: USDC/WETH .3%"
#set ylabel 'Price'
#plot \
#     'median.csv' using 2:7 with points pt 2 lt rgb '#ff0000' title 'Trades', \
#     'median.csv' using 2:4 with lines linestyle 5 title 'Uniswap3 Tick', \
#     'median.csv' using 2:8 with lines linestyle 6 title 'Quantised Tick', \

## Price comparisons

#set title "Oracle simulation, USDC/WETH .3%, 30 min window"
#plot 'median.csv' using 2:5 with lines linestyle 1 title '30m Median', \
#     'median.csv' using 2:6 with lines linestyle 3 title '30m TWAP (ours)', \
#     'uniswap.csv' using 2:6 with lines linestyle 2 title '30m TWAP (uniswap3)', \
#     'median.csv' using 2:7 with points title 'Trade', \
#     #'median.csv' using 2:8 with lines linestyle 5 title 'Current (quantised)'

## Gas scatter

#set title "Oracle read gas usage: USDC/WETH .3%, 30 min window"
#set ylabel 'Gas'
#plot 'uniswap.csv' using 2:9 with points pt 7 ps 1 lt rgb "#5e9c36" title 'Uniswap3', \
#     'median.csv' using 2:9 with points pt 7 ps 1 lt rgb "#8b1a0e" title 'Our Oracle', \

## Binary search overhead

set title "Uniswap3 gas usage at different ring buffer sizes: USDC/WETH .3%, 30 min window"
set ylabel 'Gas'
plot 'uniswap144.csv' using 2:9 with points pt 7 ps 1 lt rgb "blue" title 'Ring-Buffer Size 144', \
     'uniswap1440.csv' using 2:9 with points pt 7 ps 1 lt rgb "red" title 'Ring-Buffer Size 1440', \

## Growth/Pivot Selection

#set title "Gas Usage as Ring Buffer Accesses Increase"
#set ylabel 'Gas'
#set xlabel 'Ring Buffer Accesses'
#plot \
#    'growth-best.csv' using 2:3 with lines linestyle 1 title 'Average+Median, Best Case', \
#    'growth-rand.csv' using 2:3 with lines linestyle 3 title 'Average+Median, Random', \
#    'growth-avg-only.csv' using 2:3 with lines linestyle 4 title 'Average only', \
#    #'growth-worst.csv' using 2:3 with lines linestyle 2 title 'Worse case: O(N^2)', \
