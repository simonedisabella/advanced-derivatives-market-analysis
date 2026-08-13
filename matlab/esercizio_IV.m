clear all
clc

%% Dati di input (file e date)
file_opzioni = 'Dataset.xlsx';
file_sottostante = 'EUSTX.xlsx';

data_t0 = datetime(2025,12,11);
data_scadenza = datetime(2026,1,16);

% Tempo a scadenza seguendo la daycount c. ACT/360
tempo_a_scadenza = days(data_scadenza - data_t0)/360;

%% Leggo il file del sottostante e ricavo S0 alla data t0
tabS = readtable(file_sottostante,'Sheet','Sheet1');

if ~isdatetime(tabS.Date)
tabS.Date = datetime(tabS.Date);
end

idx0 = find(tabS.Date==data_t0,1);
if isempty(idx0)
error('La data t0 non è presente in EUSTX.xlsx (controlla la colonna Date).')
end

S0 = tabS.Price(idx0);

%% Leggo il file excel delle Call e Put e costruisco i prezzi mid
tabCall = readtable(file_opzioni,'Sheet','Sheet1','Range','A2');
tabPut  = readtable(file_opzioni,'Sheet','Sheet2','Range','A2');

strike_call = tabCall.Strike;
strike_put  = tabPut.Strike;

prezzo_mid_call = (tabCall.Bid + tabCall.Ask)/2;
prezzo_mid_put  = (tabPut.Bid  + tabPut.Ask )/2;

% Tengo solo righe valide (tolgo eventuali NaN)
okC = ~isnan(strike_call) & ~isnan(prezzo_mid_call);
okP = ~isnan(strike_put)  & ~isnan(prezzo_mid_put);
strike_call = strike_call(okC); prezzo_mid_call = prezzo_mid_call(okC);
strike_put  = strike_put(okP);  prezzo_mid_put  = prezzo_mid_put(okP);

%% Seleziono solo le opzioni OTM rispetto a S0 e applico la formula "one maturity" come specificato nella consegna
strike_otm = [strike_put(strike_put<=S0); strike_call(strike_call>S0)];
prezzi_otm = [prezzo_mid_put(strike_put<=S0); prezzo_mid_call(strike_call>S0)];

[strike_otm,ix] = sort(strike_otm);
prezzi_otm = prezzi_otm(ix);

deltaK = diff(strike_otm);
K = strike_otm(1:end-1);

vstoxx_stimato = sqrt(2/tempo_a_scadenza * sum((deltaK./(K.^2)).*prezzi_otm(1:end-1,1))) * 100;

%% Output a schermo e confronto con valore osservato
disp('Esercizio 4 (punto iv) : Stima VSTOXX con una sola scadenza (opzioni OTM)')
fprintf('Data t0: %s\n', datestr(data_t0))
fprintf('Scadenza opzioni: %s\n', datestr(data_scadenza))
fprintf('T (ACT/360): %.6f\n', tempo_a_scadenza)
fprintf('S0 (EUROSTOXX50 a t0): %.4f\n', S0)
fprintf('VSTOXX stimato (da opzioni): %.4f\n', vstoxx_stimato)

vstoxx_osservato = 15.04;
fprintf('VSTOXX osservato a t0: %.4f\n', vstoxx_osservato)
fprintf('Differenza (stimato - osservato): %.4f\n', vstoxx_stimato - vstoxx_osservato)

%% Grafico: prezzi mid Call e Put vs Strike
figure
plot(strike_call,prezzo_mid_call,'*')
hold on
plot(strike_put,prezzo_mid_put,'*')
grid on
xlabel('Strike')
ylabel('Prezzo mid')
title('Prezzi mid Call e Put vs Strike')
legend('Call mid','Put mid','Location','best')
hold off