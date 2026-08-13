clc; clear all

% Carica file Excel
Tcall=readtable("Dataset.xlsx", "Sheet", 1);
Tput=readtable("Dataset.xlsx", "Sheet",2);
TEuroStoxx=readtable("EUSTX.xlsx");
ESprice=TEuroStoxx.Price;

r=1.95634/100;  % Zero rate a un mese osservato su Bloomber
q=2.78/100; 
S0=ESprice(1,1);
T=36/365;

% Calcolo valori Mid
CallBid=Tcall.Bid;
CallAsk = Tcall.Ask; 
PutBid=Tput.Bid;
PutAsk=Tput.Ask;
CallMid=(CallBid+CallAsk)/2;
PutMid = (PutBid + PutAsk) / 2;

% Valutazione Vincoli di Merton
Kcall=Tcall.Strike;
Kput=Tput.Strike;
VincoloMertonPut=zeros(length(Kcall),1);
VincoloMertonCall=zeros(length(Kcall),1);
for i=1:length(Kcall)
 VincoloMertonPut(i,1)=max(Kput(i,1)*exp(-r*T)-S0*exp(-q*T),0);
 VincoloMertonCall(i,1)=max(S0*exp(-q*T)-Kcall(i,1)*exp(-r*T),0);
 if VincoloMertonPut(i,1)>PutMid(i,1)
  disp(sprintf("Il vincolo di Merton per le put NON è rispettato per lo strike %g", Kput(i,1)))
 end
 if VincoloMertonCall(i,1) > CallMid(i,1)
   disp(sprintf("Il vincolo di Merton per le call NON è rispettato per lo strike %g", Kcall(i,1)))
 end
% Introduzione soglia di tolleranza per vincoli di Merton
SogliaMertonPut  = (PutAsk(i)  - PutBid(i))  / 2;
SogliaMertonCall = (CallAsk(i) - CallBid(i)) / 2;
if VincoloMertonPut(i) > PutMid(i) + SogliaMertonPut
    disp(sprintf("Anche con la SOGLIA DI TOLLERANZA il vincolo di MERTON per le put NON è rispettato per lo strike %g", Kput(i,1)))
end
if VincoloMertonCall(i) > CallMid(i) + SogliaMertonCall
    disp(sprintf("Anche con la SOGLIA DI TOLLERANZA il vincolo di MERTON per le call NON è rispettato per lo strike %g", Kcall(i,1)))
end
end



% Valutazione vincoli di monotonicità
for i=1:length(CallMid)-1
 if CallMid(i,1)<=CallMid(i+1,1)
  disp("il primo vincolo di monotonicità per le call NON è rispettato")
 end
 if PutMid(i,1)>=PutMid(i+1,1)
  disp("il primo vincolo di monotonicità per le put NON è rispettato")
 end
 if CallMid(i,1) - CallMid(i+1,1) > exp(-r*T)*(Kcall(i+1,1)-Kcall(i,1))
  disp("il secondo vincolo di monotonicità per le call NON è rispettato")
 end
 if PutMid(i+1,1)-PutMid(i,1)>exp(-r*T)*(Kput(i+1,1)-Kput(i,1))
  disp("il secondo vincolo di monotonicità per le put NON è rispettato")
 end
end

% Valutazione vincolo di convessità dei prezzi rispetto allo strike in forma discreta
alfa=1;
for i=2:length(CallMid)-1
 if (CallMid(i+1,1)-CallMid(i,1))/(Kcall(i+1,1)-Kcall(i,1))<(CallMid(i,1)-CallMid(i-1,1))/(Kcall(i,1)-Kcall(i-1,1))
     disp(sprintf("Il vincolo di convessità per le call NON è rispettato per lo strike %g", Kcall(i,1)))
 end
 if (PutMid(i+1,1)-PutMid(i,1))/(Kput(i+1,1)-Kput(i,1)) < (PutMid(i,1)-PutMid(i-1,1))/(Kput(i,1)-Kput(i-1,1))
     disp(sprintf("Il vincolo di convessità per le put NON è rispettato per lo strike %g", Kput(i,1)))
 end
% Introduzione soglia di tolleranza
  sogliaPUTp=alfa*((PutAsk(i-1,1)-PutMid(i-1,1))+(PutAsk(i,1)-PutMid(i,1))+(PutAsk(i+1,1)-PutMid(i+1,1))); %sto considerando sia per la call che per la put l'half spread per costruire la soglia di tolleranza
  sogliaPUTs=sogliaPUTp/min(Kput(i,1)-Kput(i-1,1),Kput(i+1,1)-Kput(i,1));
  sogliaCALLp=alfa*((CallAsk(i-1,1)-CallMid(i-1,1))+(CallAsk(i,1)-CallMid(i,1))+(CallAsk(i+1,1)-CallMid(i+1,1)));
  sogliaCALLs = sogliaCALLp / min(Kcall(i,1) - Kcall(i-1,1), Kcall(i+1,1) - Kcall(i,1));
 if (CallMid(i+1,1)-CallMid(i,1))/(Kcall(i+1,1)-Kcall(i,1))<(CallMid(i,1)-CallMid(i-1,1))/(Kcall(i,1)-Kcall(i-1,1))-sogliaCALLs
     disp(sprintf("Anche con la SOGLIA DI TOLLERANZA il vincolo di convessità per le call NON è rispettato per lo strike %g", Kcall(i,1)))
 end
 if (PutMid(i+1,1)-PutMid(i,1))/(Kput(i+1,1)-Kput(i,1)) < (PutMid(i,1)-PutMid(i-1,1))/(Kput(i,1)-Kput(i-1,1))-sogliaPUTs
     disp(sprintf("Anche con la SOGLIA DI TOLLERANZA il vincolo di convessità per le put NON è rispettato per lo strike %g", Kput(i,1)))
 end 
end

