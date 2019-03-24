#!/bin/bash

# TODO: Add in sunrise/sunset calcuations

apiKey=""
defaultLocation=""
OpenBox="False"
Terminal="False"
HTML="False"
degreeCharacter="c"
data=0
lastUpdateTime=0
FeelsLike=0
dynamicUpdates=0
UseIcons="True"

if [ -f "$HOME/.config/weather_sh.rc" ];then
    readarray -t line < "$HOME/.config/weather_sh.rc"
    apiKey=${line[0]}
    defaultLocation=${line[1]}
    degreeCharacter=${line[2]}
    UseIcons=${line[3]}
fi

while [ $# -gt 0 ]; do
option="$1"
    case $option
    in
    -k) apiKey="$2"
    shift
    shift ;;
    -l) defaultLocation="$2"
    shift
    shift ;;
    -d) dynamicUpdates=1
    shift ;;
    -t) Terminal="True"
    shift ;;
    -h) HTML="True"
    shift ;;
    -o) OpenBox="True"
    shift ;;    
    -f) degreeCharacter="f"
    shift ;;
    esac
done

if [ -z $apiKey ];then
    echo "No API Key specified in rc, script, or command line."
    exit
fi

dataPath="/tmp/wth-$defaultLocation.json"
if [ ! -e $dataPath ];
then
    touch $dataPath
    data=$(curl "http://api.openweathermap.org/data/2.5/weather?q=$defaultLocation&units=metric&appid=$apiKey")
    echo $data > $dataPath
else
    data=$(cat $dataPath)
fi
lastUpdateTime=$(($(date +%s) -600))

while true; do
    lastfileupdate=$(date -r $dataPath +%s)
    if [ $(($(date +%s)-$lastfileupdate)) -ge 600 ];then
        data=$(curl -s "http://api.openweathermap.org/data/2.5/weather?q=$defaultLocation&units=metric&appid=$apiKey")
        echo $data > $dataPath
    fi
    if [ $(($(date +%s)-$lastUpdateTime)) -ge 600 ]; then
        lastUpdateTime=$(date +%s)
        clear
        
        Station=$(echo $data | jq -r .name)
        Lat=$(echo $data | jq -r .coord.lat)
        Long=$(echo $data | jq -r .coord.lon)
        Country=$(echo $data | jq -r .sys.country)

        ####################################################################
        # Current conditions (and icon)
        ####################################################################
        if [ "$UseIcons" = "True" ];then
            icons=$(echo $data | jq -r .weather[].icon | tr '\n' ' ')
            iconval=${icons%?}
            case $iconval in
                01*) icon="☀️";;
                02*) icon="🌤";;
                03*) icon="🌥";;
                04*) icon="☁";;
                09*) icon="🌧";;
                10*) icon="🌦";;
                11*) icon="🌩";;
                13*) icon="🌨";;
                50*) icon="🌫";;
            esac
        else
            icon=""
        fi
        ShortWeather=$(echo $data | jq -r .weather[].main | tr '\n' ' ')
        LongWeather=$(echo $data | jq -r .weather[].description | sed -E 's/\S+/\u&/g' | tr '\n' ' ')

        ####################################################################
        # Temperature
        ####################################################################
        tempinc=$(echo $data | jq -r .main.temp)   
        RawTemp=$(echo $data | jq -r .main.temp)
        temperature=$tempinc
        if  [ "$degreeCharacter" = "f" ]; then
            temperature=$(echo "scale=2; 32+1.8*$tempinc" | bc)
        fi
        
        ####################################################################
        # Parse Wind Info
        ####################################################################
        wind=$(echo $data | jq .wind.deg)
        winddir=$((2193-(${wind%.*}+45)/90))
        if [ $winddir -eq 2192 ]; then
            winddir=2190
        elif [ $winddir -eq 2190 ];then
            winddir=2192
        else
            :
        fi
        RawWindSpeed=$(echo $data | jq .wind.speed)
        WindSpeed=$(echo $data | jq .wind.speed)
        WindGusts=$(echo $data | jq .wind.gust)
        
        #Conversion
        if  [ "$degreeCharacter" = "f" ]; then
            WindSpeed=$(echo "scale=2; $WindSpeed*0.6213712" | bc | xargs printf "%.2f")
            WindGusts=$(echo "scale=2; $WindGusts*0.6213712" | bc | xargs printf "%.2f")
            windunit="mph"
        else
            WindGusts=$(echo "scale=2; $WindGusts*1" | bc)
            windunit="kph"
        fi        

        Humidity=$(echo $data | jq .main.humidity)
        CloudCover=$(echo $data | jq .clouds.all)

        ####################################################################
        # Feels Like Calculations
        # Using the raw metric value for criteria, then converting later
        ####################################################################
        # Wind Chill
        ####################################################################
        if (( $(bc -l<<<"$RawWindSpeed > 4.5") )); then #windspeed criteria for windchill
            if (( $(bc -l<<<"$RawTemp< 11") )); then #temp criteria for windchill
                FeelsLike=1
                if [ "degreeCharacter" = "f" ];then
                    WindSpeedExp=$(echo "e(0.16*l($WindSpeed))" | bc -l )
                    FeelsLikeTemp=$(echo "scale=2; 35.74 + 0.6215*$temperature - 35.75*$WindSpeedExp + 0.4275*$temperature*$WindSpeedExp" | bc | xargs printf "%.2f")
                else
                    WindSpeedExp=$(echo "e(0.16*l($WindSpeed))" | bc -l )
                    FeelsLikeTemp=$(echo "scale=2; 13.12 + 0.6215*$temperature - 11.37*$WindSpeedExp + 0.3965*$temperature*$WindSpeedExp" | bc | xargs printf "%.2f")
                fi
            fi
        fi

        ####################################################################
        # Heat Index
        # I can only find Farenheit calcuations, so....
        ####################################################################
        if  [ "$degreeCharacter" = "c" ]; then
            HITemp=$(echo "scale=2; 32+1.8*$tempinc" | bc)
        else
            HITemp=$RawTemp
        fi
        if (( $(bc -l<<<"$HITemp> 79") )); then #temp criteria for heat index
            FeelsLike=1
            FeelsLikeTemp=$(echo "scale=2;0.5 * ($HITemp + 61.0 + (($HITemp-68.0)*1.2) + ($Humidity*0.094))" | bc)
            if [ "$degreeCharacter" = "c" ];then
                FeelsLikeTemp=$(echo "scale=2; ($FeelsLikeTemp-32) / 1.8" | bc)

            fi
        fi

        ####################################################################
        # Pressure Data
        ####################################################################
        pressure=$(echo $data | jq .main.pressure)
        if  [ "$degreeCharacter" = "f" ]; then
            pressure=$(echo "scale=2; $pressure/33.863886666667" | bc)
            pressureunit="in"
        else
            pressureunit="hPa"
        fi
    fi
    AsOf=$(date +"%Y-%m-%d %R" -d @$lastfileupdate) 
    if [ "$OpenBox" = "False" ];then
        if [ "$HTML" = "False" ];then
            Terminal="True"
        fi
    fi
    if [ "$Terminal" = "True" ];then
        echo "Station: $Station, $Country $Lat / $Long"
        echo "As Of: $AsOf "  
        echo "Current Conditions: $icon $LongWeather"
        #echo "$icon $ShortWeather"
        echo "Temp: $temperature °${degreeCharacter^^}"
        if [ "$FeelsLike" = "1" ];then
            echo "Feels Like: $FeelsLikeTemp °${degreeCharacter^^}"
        fi
        echo "Pressure: $pressure $pressureunit"
        echo -e \\u$winddir "$WindSpeed$windunit Gusts: $WindGusts$windunit"
        echo "Humidity: $Humidity%"
        echo "Cloud Cover: $CloudCover%"
    fi
    if [ "$OpenBox" = "True" ]; then
        echo '<openbox_pipe_menu>' 
        echo '<separator label="Weather" />' 
        printf '<item label="Station: %s, %s" />\n' "$Station" "$Country"  
        printf '<item label="As of %s" />\n' "$AsOf" 
        printf '<item label="Now: %s %s" />\n' "$icon" "$LongWeather" 
        printf '<item label="Temp: %s%s" />\n' "$temperature" "°${degreeCharacter^^}" 
        if [ "$FeelsLike" = "1" ];then
            printf '<item label="Feels Like: %s%s" />\n' "$FeelsLikeTemp" "°${degreeCharacter^^}" 
        fi
        printf '<item label="Pressure: %s%s" />\n' "$pressure" "$pressureunit" 
        printf '<item label="Wind: %s%s Gusts: %s%s" />\n'  "$WindSpeed" "$windunit" "$WindGusts" "$windunit" 
        printf '<item label="Humidity: %s%%" />\n' "$Humidity" 
        printf '<item label="Cloud Cover: %s%%" />\n' "$CloudCover" 
        echo '</openbox_pipe_menu>' 
    fi
    if [ "$HTML" = "True" ];then
        echo "Station: $Station, $Country $Lat / $Long <br  />"  
        echo "As Of: $AsOf <br  />"  
        echo "Current Conditions: $icon $LongWeather <br  />" 
        #echo "$icon $ShortWeather" 
        echo "Temp: $temperature °${degreeCharacter^^} <br  />" 
        if [ "$FeelsLike" = "1" ];then
            echo "Feels Like: $FeelsLikeTemp °${degreeCharacter^^} <br  />"
        fi
        echo "Pressure: $pressure $pressureunit <br  />" 
        echo -e \\u$winddir "$WindSpeed$windunit Gusts: $WindGusts$windunit <br  />" 
        echo "Humidity: $Humidity% <br  />" 
        echo "Cloud Cover: $CloudCover% <br  />"     
    fi
    if [ $dynamicUpdates -eq 0 ];then
        break
    fi    
done
