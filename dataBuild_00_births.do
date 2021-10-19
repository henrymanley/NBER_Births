/*
Creates 1948-1988 births data by extracting Natality data from NBER's website. 

This data is weighted by reported % sample for each state-year. That is, if the 1972 
natality reports that NY births were measured with a 50% sample the idea is that 
the number of births in NY 1972 gets weighted 2x. 

These extracted data are plotted against available DHSS national aggregates.

-- 
Henry Manley - hjm67@cornell.edu
Created 8/1/21
Last Modified 10/13/21 
*/

cd "$rawData"
clear
set more off 

/*------------------------------------------------------------------------------
NBER Data Requests
------------------------------------------------------------------------------*/

/* NBER Natality 1960-1967 */
tempfile yearAccumData6067
forval y=60/67 {
	qui{
		nois di "`y'" 
		use "https://data.nber.org/data/births/1940-1968/births_data/5_births_data-cleaned_stata/clean_natality19`y'.dta"	
		
		if `y' == 60 { 
			save `yearAccumData6067', replace
			} 
		
		else { 
			append using `yearAccumData6067', force 
			save `yearAccumData6067', replace 
		} 
	}
} 

* Clean
use `yearAccumData6067', clear 
drop if county == "total" 
keep if sub_county == "total" | sub_county == "" 
keep year births county state race
replace race = "total" if race == ""
gen newRace = (race != "total" 1) 
replace newRace = 2 if race == "nonwhite"  
drop race 
rename newRace race  
collapse (sum) births, by(race county state year)
replace state = upper(state) 
replace county = upper(county) 
save `yearAccumData6067', replace 


/* NBER Natality 1968-1988 */
forval y=1968/1988 {
	qui{
		nois di "**************`y'**************" 
		copy "https://data.nber.org/natality/`y'/natl`y'.dta.zip" temp`y'.zip, replace 
		
		unzipfile temp`y'.zip, replace 
		use natl`y'.dta, clear 
		gen year = `y'
		
		* Territories
		gen cnt=substr(cntyres, 3, 3) 
		drop if cnt == "ZZZ" 
		drop cnt statenat cntynat 

		* Destring
		foreach v in stresfip cntyrfip { 
			capture confirm string variable `v' 
			if !_rc { 
				destring `v', replace 
			} 
		} 
		
		* Check for weights. Generate = 1 if missing
		capture confirm variable recwt 
		if _rc {
			gen recwt = 1
		} 
		
		* Clean stateoc & countyoc
		sort stateres 
		rename cntyres countyres
		
		loc len = strlen(stateres) + 1
		replace countyres = substr(countyres, `len', strlen(countyres))			
		keep year stateres countyres crace* recwt

		gen births = recwt
		gen race = crace3
		
		* Get total counts by weighting births
		preserve 
		
		collapse (sum) births, by(stateres countyres year)

		gen race = 0 
		gen recwt = 1
	
		* Year state county aggregates
		tempfile aggregates 
		save `aggregates', replace 
		restore
		
		* Append non-race aggregated births
		append using `aggregates'
		collapse (sum) births, by(stateres countyres year race)
		
		if `y' == 1968 { 
			tempfile yearAccumData6888
			save `yearAccumData6888', replace 
		} 
		else { 
			append using `yearAccumData6888', force 
			save `yearAccumData6888', replace 
		} 
		cap erase natl`y'.dta 
		cap erase temp`y'.zip  
		}
		
}


/*------------------------------------------------------------------------------
Data Cleaning
------------------------------------------------------------------------------*/

* Load in made data
use `yearAccumData6888', clear
save "births", replace

* Merge crosswalk
use "https://data.nber.org/mortality/nchs2fips_county1990.dta", replace 
rename stateoc stateres
rename countyoc countyres
merge 1:m stateres countyres using "births"

* Destring fips
destring fipsco, replace
rename fipsco fips 

* All that 60-67 has for ID info is state and county name. Need to match that here.
sort stateres countyres
replace statename = statename[_n-1] if statename[_n] == ""
gen county = upper(countyname)
gen state = upper(statename)
drop countyname statename
drop _me 

* Bring all natality data together
save "births", replace
append using `yearAccumData6067'
keep *res* fips state county year births race
order fips *res* state county year births race

* Fill in missing state/county level identifiers
gsort state county -year
replace stateres = stateres[_n-1] if stateres[_n] == "" & state[_n] == state[_n - 1]
replace countyres = countyres[_n-1] if countyres[_n] == ""
replace fips = fips[_n-1] if fips[_n] == .

* Drop unneeded vars
replace births = 2*births if inrange(year, 1968, 1971)
label var race "Race: 0 == Total, 1 == White, 2 == Nonwhite"

* Fix NYC 
replace fips = 36061 if fips == 36

* Fix Alleutian Islands 
replace fips = 2013 if fips == 2010

sort fips year
isid fips year race 
save "births", replace
