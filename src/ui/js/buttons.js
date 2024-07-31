
function runInput() {
    const input_area = document.getElementById("codeinput");
    const new_code =  input_area.value;

    bf_exec(new_code).then((res) => {
        const out = document.getElementById("output-scroll");
        window.alert("'"+res+"'"+typeof(res));
        out.value = out.value + res;
        input_area.value = "";
    });
}
